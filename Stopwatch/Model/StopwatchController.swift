//
//  StopwatchController.swift
//  Stopwatch
//

import Foundation
import Observation
import SwiftUI
import UIKit
import UserNotifications

/// 碼表 + 多組提醒排程的核心邏輯。
///
/// 碼表本身以「起算時間點」推算經過秒數，因此響鈴、切到背景、鎖定螢幕都不會影響計時，
/// 提醒響完之後碼表也一律繼續往前跑。
@Observable
final class StopwatchController {

    // MARK: - 碼表狀態

    private(set) var isRunning = false
    private var startedAt: Date?
    private var accumulated: TimeInterval = 0

    /// 這一輪碼表最初起跑的絕對時刻（暫停不會改變它，重置才會清掉）。
    /// 各排程設定的時鐘時刻就是換算成「距離這個原點幾秒」放到碼表時間軸上。
    private(set) var sessionStart: Date?

    /// 還在等待時，「第一次響鈴」的絕對時刻。
    ///
    /// 存起來而不是每次重算：使用者多半會關掉 App 等它響，回來時得知道
    /// 那個時刻已經過了，而不是傻傻地把它算成明天同一時間。
    private(set) var armedAnchor: Date?

    /// 由計時器推動的畫面時間，用來觸發 SwiftUI 更新。
    private(set) var displayNow = Date()

    /// 目前碼表秒數（畫面用）。
    var elapsed: TimeInterval {
        accumulated + (startedAt.map { displayNow.timeIntervalSince($0) } ?? 0)
    }

    /// 目前碼表秒數（即時計算，用於判斷響鈴）。
    private var preciseElapsed: TimeInterval {
        accumulated + (startedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    // MARK: - 排程與紀錄

    var schedules: [AlarmSchedule] = [] {
        didSet {
            // init 期間先不要有副作用：存檔的碼表狀態還沒讀回來。
            guard isInitialised, schedules != oldValue else { return }
            persistSchedules()
            // 排程改動可能換掉最早的那一組，等待中的時刻與計時器都要跟著調整。
            refreshArmedAnchor()
            persistRunState()
            startTicker()
        }
    }

    private(set) var events: [FireEvent] = []

    /// 最近一次響鈴，用來在畫面上閃一下提示。
    private(set) var flash: RingFlash?

    struct RingFlash: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let colorIndex: Int
        let at: TimeInterval
    }

    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - 內部狀態

    private enum Keys {
        // v2：第一次響鈴由「碼表秒數」改成「時鐘時刻」，舊資料無法對應，直接換一個鍵。
        static let schedules = "schedules.v2"
        static let runState = "stopwatch.run.v2"
    }

    /// 存檔用的碼表狀態，App 被系統終止之後可以接回原本的時間軸。
    private struct RunState: Codable {
        var isRunning: Bool
        var accumulated: TimeInterval
        var startedAt: Date?
        /// 這一輪碼表最初起跑的絕對時刻，用來換算各排程的第一次響鈴落在碼表的第幾秒。
        var sessionStart: Date?
        var armedAnchor: Date?
    }

    /// 超過這個長度就當作是上次忘了停，重新歸零而不是接一個天文數字回來。
    private static let maxRestorableElapsed: TimeInterval = 24 * 60 * 60

    private var ticker: Timer?
    private var lastCheckedElapsed: TimeInterval = 0
    private var flashResetWorkItem: DispatchWorkItem?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// 下一次 tick 是不是「從背景回來的補算」。背景期間的提醒已經由通知響過，
    /// 補算時只補登紀錄、不再出聲。
    private var isCatchingUp = false
    private var isInitialised = false

    /// 本地通知一次最多只會保留 64 則，這裡預留一些空間。
    private let maxScheduledNotifications = 58

    init() {
        schedules = Self.loadSchedules()
        restoreRunState()
        if armedAnchor == nil { refreshArmedAnchor() }
        isInitialised = true
    }

    /// App 啟動時呼叫。
    func handleLaunch() {
        // 上一輪排進系統的提醒通知已經沒有意義：前景一律由 App 自己響，
        // 再次進背景時會重排。不清掉的話 App 被系統終止過就會冒出對不上的提醒。
        cancelPendingNotifications()
        refreshNotificationStatus()
        requestNotificationPermissionIfNeeded()

        catchUpArmedStartIfNeeded()
        // 執行中要接回碼表；等待中要盯著時鐘，兩種都需要計時器。
        startTicker()
        applyIdleTimer()
    }

    // MARK: - 碼表控制

    func toggleRunning() {
        isRunning ? pause() : start()
    }

    /// 手動按「開始」：不等時鐘，現在就當作碼表的起點。
    func start() {
        guard !isRunning else { return }
        let now = Date()
        startedAt = now
        if sessionStart == nil { sessionStart = now }
        isRunning = true
        lastCheckedElapsed = accumulated
        displayNow = now

        startTicker()
        applyIdleTimer()
        persistRunState()
    }

    /// 時鐘走到最早一組排程的「第一次響鈴」時刻，碼表自動從 0 開始跑。
    ///
    /// `catchingUp` 代表這個時刻是在 App 沒在前景時過掉的：那幾響已經由通知送出，
    /// 這裡只補登紀錄，不再重複出聲。
    private func autoStart(at moment: Date, catchingUp: Bool) {
        sessionStart = moment
        armedAnchor = nil
        startedAt = moment
        accumulated = 0
        isRunning = true
        displayNow = Date()

        // 第一次響鈴落在碼表的第 0 秒，而 fireTimes 只收「> from」的時間點，
        // 所以起算點要往前挪一點，那一響才不會被跳過。
        let now = preciseElapsed
        fireDueAlarms(from: -1, to: now, catchingUp: catchingUp)
        lastCheckedElapsed = now

        startTicker()
        applyIdleTimer()
        persistRunState()
    }

    func pause() {
        guard isRunning else { return }
        accumulated = preciseElapsed
        startedAt = nil
        isRunning = false
        displayNow = Date()

        stopTicker()
        cancelPendingNotifications()
        applyIdleTimer()
        persistRunState()
    }

    /// 重置：碼表歸零、清除紀錄，並重新等待下一次的「第一次響鈴」時刻。
    func reset() {
        stopTicker()
        isRunning = false
        startedAt = nil
        sessionStart = nil
        accumulated = 0
        lastCheckedElapsed = 0
        displayNow = Date()
        events.removeAll()
        flash = nil
        refreshArmedAnchor()

        SoundPlayer.shared.stopAll()
        cancelPendingNotifications()
        applyIdleTimer()
        persistRunState()
        startTicker()            // 回到等待狀態，還是要盯著時鐘
    }

    // MARK: - 碼表狀態存檔

    private func persistRunState() {
        let state = RunState(isRunning: isRunning,
                             accumulated: accumulated,
                             startedAt: startedAt,
                             sessionStart: sessionStart,
                             armedAnchor: armedAnchor)
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Keys.runState)
    }

    /// 只還原資料，計時器與螢幕鎖定留給 `handleLaunch()`，避免在 App 還沒啟動完就碰 `UIApplication`。
    private func restoreRunState() {
        guard let data = UserDefaults.standard.data(forKey: Keys.runState),
              let state = try? JSONDecoder().decode(RunState.self, from: data) else { return }

        accumulated = max(state.accumulated, 0)
        startedAt = state.isRunning ? state.startedAt : nil
        isRunning = state.isRunning && state.startedAt != nil
        sessionStart = state.sessionStart
        armedAnchor = state.armedAnchor
        displayNow = Date()

        guard preciseElapsed <= Self.maxRestorableElapsed else {
            accumulated = 0
            startedAt = nil
            sessionStart = nil
            armedAnchor = nil
            isRunning = false
            persistRunState()
            return
        }

        // 紀錄本身沒有存檔，冷啟動時就不補登背景期間響過的提醒，只把時間軸接回來。
        lastCheckedElapsed = preciseElapsed
    }

    // MARK: - 計時器

    /// 執行中要 30fps 推動碼表數字；只是在等第一次響鈴時，每秒看一次時鐘就夠了。
    private func startTicker() {
        stopTicker()
        guard isRunning || isArmed else { return }

        let timer = Timer(timeInterval: isRunning ? 1.0 / 30.0 : 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async { self.tick() }
        }
        // .common 讓使用者捲動畫面時碼表照樣更新
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        displayNow = Date()

        guard isRunning else {
            // 還沒開始：盯著時鐘，到了最早一組排程的時刻就自動起跑。
            if let anchor = armedAnchor, anchor <= Date() {
                autoStart(at: anchor, catchingUp: false)
            }
            return
        }

        let now = preciseElapsed
        fireDueAlarms(from: lastCheckedElapsed, to: now, catchingUp: isCatchingUp)
        lastCheckedElapsed = now
        isCatchingUp = false
    }

    // MARK: - 響鈴

    private func fireDueAlarms(from: TimeInterval, to now: TimeInterval, catchingUp: Bool) {
        guard now > from else { return }

        var due: [(schedule: AlarmSchedule, time: TimeInterval)] = []
        for schedule in schedules where schedule.isEnabled {
            for time in schedule.fireTimes(firstFire: firstFireElapsed(for: schedule),
                                           after: from,
                                           through: now) {
                due.append((schedule, time))
            }
        }
        guard !due.isEmpty else { return }
        due.sort { $0.time < $1.time }

        for item in due {
            // 只有「剛從背景回來、而且這個時間點確實已經過去」才算是通知響過的，
            // 這裡不能單看落後多少秒：前景偶爾卡頓也會落後，那時候該響的還是要響。
            let deliveredByNotification = catchingUp && (now - item.time) > 0.5
            record(item.schedule, at: item.time, missed: deliveredByNotification)
            if !deliveredByNotification {
                ring(item.schedule, at: item.time)
            }
        }
    }

    private func record(_ schedule: AlarmSchedule, at time: TimeInterval, missed: Bool) {
        let event = FireEvent(scheduleID: schedule.id,
                              label: schedule.displayLabel,
                              at: time,
                              colorIndex: schedule.colorIndex,
                              deliveredInBackground: missed)
        events.insert(event, at: 0)
        if events.count > 200 {
            events.removeLast(events.count - 200)
        }
    }

    private func ring(_ schedule: AlarmSchedule, at time: TimeInterval) {
        if let option = SoundCatalog.resolved(id: schedule.soundID) {
            SoundPlayer.shared.play(option, times: schedule.chimeCount)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        flash = RingFlash(label: schedule.displayLabel, colorIndex: schedule.colorIndex, at: time)
        flashResetWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flash = nil }
        flashResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    /// 試聽某一組排程的鈴聲。
    func preview(_ schedule: AlarmSchedule) {
        guard let option = SoundCatalog.resolved(id: schedule.soundID) else { return }
        SoundPlayer.shared.preview(option)
    }

    // MARK: - 第一次響鈴與下一次提醒

    /// 有啟用的排程、而且這一輪還沒起跑 —— 也就是正在等時鐘走到第一次響鈴。
    var isArmed: Bool {
        sessionStart == nil && armedAnchor != nil
    }

    /// 等待中時，最早會響的那一組排程與它的絕對時刻。
    var armedFirstFire: (schedule: AlarmSchedule, date: Date)? {
        guard sessionStart == nil, let anchor = armedAnchor else { return nil }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: anchor)
        guard let schedule = schedules.first(where: {
            $0.isEnabled && $0.firstHour == parts.hour && $0.firstMinute == parts.minute
        }) else { return nil }
        return (schedule, anchor)
    }

    /// 重新推算等待中的第一次響鈴時刻。已經起跑的話就沒有等待可言。
    private func refreshArmedAnchor() {
        guard sessionStart == nil else {
            armedAnchor = nil
            return
        }
        let now = Date()
        armedAnchor = schedules
            .filter(\.isEnabled)
            .compactMap { $0.firstFireDate(onOrAfter: now) }
            .min()
    }

    /// 等待期間 App 可能整個被關掉，回來時要把「已經到點」這件事補起來。
    private func catchUpArmedStartIfNeeded() {
        guard sessionStart == nil else { return }
        if armedAnchor == nil { refreshArmedAnchor() }

        guard let anchor = armedAnchor, anchor <= Date() else { return }

        // 隔了太久沒開 App，就不要硬接一個幾天前的時間軸，直接等下一次。
        guard Date().timeIntervalSince(anchor) <= Self.maxRestorableElapsed else {
            refreshArmedAnchor()
            persistRunState()
            return
        }
        autoStart(at: anchor, catchingUp: true)
    }

    /// 這組排程的第一次響鈴落在碼表的第幾秒。
    func firstFireElapsed(for schedule: AlarmSchedule) -> TimeInterval {
        guard let sessionStart else { return 0 }
        return schedule.firstFireElapsed(stopwatchStart: sessionStart)
    }

    /// 所有排程中最接近的下一次響鈴（碼表時間軸）。
    var nextFire: (schedule: AlarmSchedule, time: TimeInterval)? {
        let now = elapsed
        var best: (schedule: AlarmSchedule, time: TimeInterval)?
        for schedule in schedules where schedule.isEnabled {
            guard let time = nextFireTime(for: schedule), time > now else { continue }
            if best == nil || time < best!.time {
                best = (schedule, time)
            }
        }
        return best
    }

    /// 下一次響鈴的絕對時刻，用在「還很久」時改顯示時鐘時間而不是一長串倒數。
    func nextFireDate(for schedule: AlarmSchedule) -> Date? {
        guard let sessionStart, let time = nextFireTime(for: schedule) else { return nil }
        return sessionStart.addingTimeInterval(time)
    }

    func nextFireTime(for schedule: AlarmSchedule) -> TimeInterval? {
        guard sessionStart != nil else { return nil }
        return schedule.upcomingFireTimes(firstFire: firstFireElapsed(for: schedule),
                                          after: elapsed,
                                          limit: 1).first
    }

    func firedCount(for schedule: AlarmSchedule) -> Int {
        events.filter { $0.scheduleID == schedule.id }.count
    }

    // MARK: - 排程管理

    func addSchedule(_ schedule: AlarmSchedule) {
        var new = schedule
        new.colorIndex = schedules.count
        schedules.append(new)
        requestNotificationPermissionIfNeeded()
    }

    func update(_ schedule: AlarmSchedule) {
        guard let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        schedules[index] = schedule
    }

    func delete(_ schedule: AlarmSchedule) {
        schedules.removeAll { $0.id == schedule.id }
    }

    func delete(atOffsets offsets: IndexSet) {
        schedules.remove(atOffsets: offsets)
    }

    func setEnabled(_ enabled: Bool, for schedule: AlarmSchedule) {
        guard let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        schedules[index].isEnabled = enabled
    }

    private func persistSchedules() {
        guard let data = try? JSONEncoder().encode(schedules) else { return }
        UserDefaults.standard.set(data, forKey: Keys.schedules)
    }

    private static func loadSchedules() -> [AlarmSchedule] {
        guard let data = UserDefaults.standard.data(forKey: Keys.schedules),
              let decoded = try? JSONDecoder().decode([AlarmSchedule].self, from: data) else {
            return [defaultSchedule()]
        }
        return decoded
    }

    private static func defaultSchedule() -> AlarmSchedule {
        var schedule = AlarmSchedule.makeNew()
        schedule.label = "每 5 分鐘"
        schedule.interval = 300
        schedule.repeats = true
        return schedule
    }

    // MARK: - 背景行為

    private func applyIdleTimer() {
        // 碼表執行時不讓螢幕自動鎖定：鎖定後就只能靠通知響鈴，前景的連響與畫面提示都會失效。
        UIApplication.shared.isIdleTimerDisabled = isRunning
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            displayNow = Date()
            cancelPendingNotifications()
            refreshNotificationStatus()
            catchUpArmedStartIfNeeded()   // 背景期間可能已經走到第一次響鈴的時刻
            startTicker()
            if isRunning { tick() }       // 補登在背景期間響過的提醒
            isCatchingUp = false
        case .background:
            isCatchingUp = true
            scheduleBackgroundNotifications()
        default:
            break
        }
    }

    // MARK: - 本地通知

    func requestNotificationPermissionIfNeeded() {
        // 不要 .badge：App 從來不設角標，多要一個權限只會讓授權對話框看起來更可疑。
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            self?.refreshNotificationStatus()
        }
    }

    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { [weak self] in
                self?.notificationStatus = settings.authorizationStatus
            }
        }
    }

    /// 排通知是非同步的，進背景後主佇列很快就被凍結。
    /// 用背景任務把時間撐到整批排完為止，否則會整段背景都不響。
    private func beginBackgroundTask() {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "schedule-reminders") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// 接下來每一次響鈴的絕對時刻。執行中是從碼表往後推；還在等待則是從
    /// 預定的第一次響鈴時刻往後推 —— 後者讓使用者不必把 App 開著也會響。
    private func upcomingFireMoments(limit: Int) -> [(schedule: AlarmSchedule, time: TimeInterval, date: Date)] {
        let origin: Date
        let from: TimeInterval

        if isRunning {
            origin = Date().addingTimeInterval(-preciseElapsed)
            from = preciseElapsed
        } else if let anchor = armedAnchor {
            origin = anchor
            from = -1                // 讓落在第 0 秒的第一響也算進去
        } else {
            return []                // 暫停中：碼表沒在走，不排任何通知
        }

        var upcoming: [(schedule: AlarmSchedule, time: TimeInterval, date: Date)] = []
        for schedule in schedules where schedule.isEnabled {
            let firstFire = schedule.firstFireElapsed(stopwatchStart: origin)
            for time in schedule.upcomingFireTimes(firstFire: firstFire, after: from, limit: limit) {
                upcoming.append((schedule, time, origin.addingTimeInterval(time)))
            }
        }
        upcoming.sort { $0.date < $1.date }
        return Array(upcoming.prefix(limit))
    }

    /// 進背景時，把接下來的響鈴時間點排成本地通知（iOS 上限 64 則）。
    private func scheduleBackgroundNotifications() {
        beginBackgroundTask()
        let batch = upcomingFireMoments(limit: maxScheduledNotifications)

        UNUserNotificationCenter.current().replacePending(withPrefix: NotificationID.reminder) {
            batch.compactMap { item in
                let delay = item.date.timeIntervalSinceNow
                guard delay > 0.5 else { return nil }

                let content = UNMutableNotificationContent()
                content.title = item.schedule.displayLabel
                content.body = TimeFormat.timeOfDay(item.date)
                content.interruptionLevel = .timeSensitive
                content.sound = Self.notificationSound(for: item.schedule)

                return UNNotificationRequest(
                    identifier: "\(NotificationID.reminder)\(item.schedule.id.uuidString)-\(Int(item.time.rounded()))",
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                )
            }
        } completion: { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private static func notificationSound(for schedule: AlarmSchedule) -> UNNotificationSound {
        SoundCatalog.notificationSound(for: schedule.soundID)
    }

    private func cancelPendingNotifications() {
        UNUserNotificationCenter.current().removePending(withPrefix: NotificationID.reminder)
    }
}
