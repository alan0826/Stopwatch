//
//  ReminderController.swift
//  Stopwatch
//

import Foundation
import Observation
import SwiftUI
import UIKit
import UserNotifications

/// 多組提醒排程的核心邏輯。
///
/// 時間一律以時鐘為準，沒有碼表也沒有「開始／暫停」——每組排程自己的開關就是它的開關。
/// App 在前景時由自己播鈴聲，切到背景則把接下來的響鈴排成本地通知。
@Observable
final class ReminderController {

    /// 由計時器推動的現在時刻，畫面上的時鐘與倒數都看它。
    private(set) var now = Date()

    var schedules: [AlarmSchedule] = [] {
        didSet {
            guard isInitialised, schedules != oldValue else { return }
            persistSchedules()
        }
    }

    private(set) var events: [FireEvent] = []

    /// 最近一次響鈴，用來在畫面上閃一下提示。
    private(set) var flash: RingFlash?

    struct RingFlash: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let colorIndex: Int
        let at: Date
    }

    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - 內部狀態

    private enum Keys {
        // v3：改以時鐘時刻為準，不再有碼表時間軸，舊資料對不上。
        static let schedules = "schedules.v3"
        static let events = "events.v3"
        static let lastChecked = "reminders.lastChecked.v3"
    }

    /// 上一次檢查到哪個時刻為止。存檔之後，App 被關掉期間響過的也補得回來。
    private var lastCheckedAt = Date()

    /// App 離開前景的時刻。回到前景並補算完才清掉。
    private var backgroundedAt: Date?

    private var ticker: Timer?
    private var flashResetWorkItem: DispatchWorkItem?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var isInitialised = false

    /// 本地通知一次最多只會保留 64 則，這裡預留一些空間。
    private let maxScheduledNotifications = 58

    init() {
        schedules = Self.loadSchedules()
        events = Self.loadEvents()
        lastCheckedAt = UserDefaults.standard.object(forKey: Keys.lastChecked) as? Date ?? Date()
        isInitialised = true

        // 這裡只補上還沒安排的那一輪，不收掉已經跑完的。
        // 收尾要等 handleLaunch() 補登完紀錄之後才做，否則 App 關著期間跑完的那一輪
        // 會先被停用，接著補登時就找不到啟用中的排程，那幾次響鈴等於憑空消失。
        normalizeCycles(retiringFinished: false)
        persistSchedules()
    }

    /// App 啟動時呼叫。
    func handleLaunch() {
        // 上一輪排進系統的提醒通知已經沒有意義：前景一律由 App 自己響，
        // 再次進背景時會重排。
        cancelPendingNotifications()
        refreshNotificationStatus()
        requestNotificationPermissionIfNeeded()

        tick()          // 補登 App 沒開著的期間響過的提醒
        startTicker()
    }

    // MARK: - 計時

    /// 畫面上的時鐘只到秒，每秒跑一次就夠了。
    ///
    /// 不管有沒有啟用的排程都要跑：那個時鐘是一直在走的，不能因為沒排程就凍住。
    private func startTicker() {
        stopTicker()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async { self.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        now = Date()
        fireDueAlarms(from: lastCheckedAt, to: now)
        lastCheckedAt = now
        UserDefaults.standard.set(lastCheckedAt, forKey: Keys.lastChecked)
        normalizeCycles()
    }

    // MARK: - 每一輪的起點

    /// 幫還沒安排的排程排上這一輪，並把已經跑完的一輪推到隔天或直接關掉。
    ///
    /// `retiringFinished` 為 false 時只做前半段 —— 補登紀錄之前不能先把排程收掉。
    private func normalizeCycles(retiringFinished: Bool = true) {
        let moment = Date()
        var updated = schedules
        var changed = false

        for index in updated.indices {
            var schedule = updated[index]

            guard schedule.isEnabled else {
                if schedule.cycleStart != nil {
                    schedule.cycleStart = nil
                    updated[index] = schedule
                    changed = true
                }
                continue
            }

            guard let start = schedule.cycleStart else {
                schedule.cycleStart = schedule.firstFireDate(onOrAfter: moment)
                updated[index] = schedule
                changed = true
                continue
            }

            // 這一輪還有下一次就不用動。
            guard retiringFinished,
                  schedule.nextFireDate(cycleStart: start, after: moment) == nil
            else { continue }

            if schedule.repeatsDaily {
                schedule.cycleStart = schedule.firstFireDate(onOrAfter: moment)
            } else {
                // 跑完了就把自己關掉，不然開關會一直開著卻再也不會響。
                schedule.isEnabled = false
                schedule.cycleStart = nil
            }
            updated[index] = schedule
            changed = true
        }

        if changed { schedules = updated }
    }

    // MARK: - 響鈴

    private func fireDueAlarms(from: Date, to moment: Date) {
        guard moment > from else { return }

        var due: [(schedule: AlarmSchedule, at: Date)] = []
        for schedule in schedules where schedule.isEnabled {
            guard let start = schedule.cycleStart else { continue }
            for date in schedule.fireDates(cycleStart: start, after: from, through: moment) {
                due.append((schedule, date))
            }
        }
        guard !due.isEmpty else { return }
        due.sort { $0.at < $1.at }

        for item in due {
            let delivered = wasDeliveredByNotification(fireDate: item.at)
            record(item.schedule, at: item.at, missed: delivered)
            if !delivered {
                ring(item.schedule, at: item.at)
            }
        }
        persistEvents()
    }

    /// 這一響是不是已經由系統通知送出了？是的話回到前景就不該再響一次。
    ///
    /// 兩個條件任一成立就算：
    /// 1. 落後超過兩秒。前景時計時器每秒都會跑，落後這麼多必然是 App 當時不在前景，
    ///    這也涵蓋了「被系統終止後重新啟動」。
    /// 2. 響鈴的時刻落在 App 離開前景之後。背景剛開始的幾秒 App 其實還活著
    ///    （排通知的背景任務把它撐著），那時候響的也是通知在響。
    private func wasDeliveredByNotification(fireDate: Date) -> Bool {
        if Date().timeIntervalSince(fireDate) > 2 { return true }
        guard let backgroundedAt else { return false }
        return fireDate >= backgroundedAt.addingTimeInterval(-0.5)
    }

    private func record(_ schedule: AlarmSchedule, at date: Date, missed: Bool) {
        let event = FireEvent(scheduleID: schedule.id,
                              label: schedule.displayLabel,
                              firedAt: date,
                              colorIndex: schedule.colorIndex,
                              deliveredInBackground: missed)
        events.insert(event, at: 0)
        if events.count > 200 {
            events.removeLast(events.count - 200)
        }
    }

    private func ring(_ schedule: AlarmSchedule, at date: Date) {
        if let option = SoundCatalog.resolved(id: schedule.soundID) {
            SoundPlayer.shared.play(option, times: schedule.chimeCount)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        flash = RingFlash(label: schedule.displayLabel, colorIndex: schedule.colorIndex, at: date)
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

    // MARK: - 下一次提醒

    func nextFireDate(for schedule: AlarmSchedule) -> Date? {
        guard let start = schedule.cycleStart else { return nil }
        return schedule.nextFireDate(cycleStart: start, after: now)
    }

    /// 所有排程中最接近的下一次響鈴。
    var nextFire: (schedule: AlarmSchedule, at: Date)? {
        var best: (schedule: AlarmSchedule, at: Date)?
        for schedule in schedules where schedule.isEnabled {
            guard let date = nextFireDate(for: schedule) else { continue }
            if best == nil || date < best!.at {
                best = (schedule, date)
            }
        }
        return best
    }

    func firedCount(for schedule: AlarmSchedule) -> Int {
        events.filter { $0.scheduleID == schedule.id }.count
    }

    // MARK: - 排程管理

    func addSchedule(_ schedule: AlarmSchedule) {
        var new = schedule
        new.colorIndex = schedules.count
        new.cycleStart = nil
        schedules.append(new)
        normalizeCycles()
        requestNotificationPermissionIfNeeded()
    }

    func update(_ schedule: AlarmSchedule) {
        guard let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        var updated = schedule
        updated.cycleStart = nil        // 時刻可能改過了，這一輪重排
        schedules[index] = updated
        normalizeCycles()
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
        schedules[index].cycleStart = nil
        normalizeCycles()
    }

    func clearHistory() {
        events.removeAll()
        persistEvents()
    }

    // MARK: - 儲存

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

    private func persistEvents() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        UserDefaults.standard.set(data, forKey: Keys.events)
    }

    private static func loadEvents() -> [FireEvent] {
        guard let data = UserDefaults.standard.data(forKey: Keys.events),
              let decoded = try? JSONDecoder().decode([FireEvent].self, from: data) else {
            return []
        }
        return decoded
    }

    // MARK: - 前景／背景

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            cancelPendingNotifications()
            refreshNotificationStatus()
            tick()                      // 補登不在前景時響過的提醒
            backgroundedAt = nil
            startTicker()
        case .background:
            backgroundedAt = Date()
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

    /// 進背景時，把接下來的響鈴時刻排成本地通知（iOS 上限 64 則）。
    private func scheduleBackgroundNotifications() {
        beginBackgroundTask()

        let moment = Date()
        var upcoming: [(schedule: AlarmSchedule, at: Date)] = []
        for schedule in schedules where schedule.isEnabled {
            guard let start = schedule.cycleStart else { continue }
            for date in schedule.upcomingFireDates(cycleStart: start,
                                                   after: moment,
                                                   limit: maxScheduledNotifications) {
                upcoming.append((schedule, date))
            }
        }
        upcoming.sort { $0.at < $1.at }
        let batch = Array(upcoming.prefix(maxScheduledNotifications))

        UNUserNotificationCenter.current().replacePending(withPrefix: NotificationID.reminder) {
            batch.compactMap { item in
                let delay = item.at.timeIntervalSinceNow
                guard delay > 0.5 else { return nil }

                let content = UNMutableNotificationContent()
                content.title = item.schedule.displayLabel
                content.body = TimeFormat.timeOfDay(item.at)
                content.interruptionLevel = .timeSensitive
                content.sound = SoundCatalog.notificationSound(for: item.schedule.soundID)

                return UNNotificationRequest(
                    identifier: "\(NotificationID.reminder)\(item.schedule.id.uuidString)-\(Int(item.at.timeIntervalSince1970))",
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                )
            }
        } completion: { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func cancelPendingNotifications() {
        UNUserNotificationCenter.current().removePending(withPrefix: NotificationID.reminder)
    }
}
