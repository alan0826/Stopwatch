//
//  ReminderController.swift
//  Stopwatch
//

import Foundation
import Observation
import SwiftUI
import UIKit
import UserNotifications
import AlarmKit
import OSLog

enum AlarmPermissionStatus: Equatable {
    case unavailable
    case notDetermined
    case denied
    case authorized
}

/// 多組提醒排程的核心邏輯。
///
/// 時間一律以時鐘為準，沒有碼表也沒有「開始／暫停」——每組排程自己的開關就是它的開關。
/// 一般提醒預先排成本地通知，由系統統一播放，避免鎖定切換時漏響。
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
    private(set) var notificationSettingsLoaded = false
    private(set) var notificationAlertsEnabled = false
    private(set) var notificationSoundsEnabled = false
    private(set) var notificationLockScreenEnabled = false
    private(set) var notificationTimeSensitiveEnabled = false
    private(set) var notificationScheduledDeliveryEnabled = false
    private(set) var alarmPermissionStatus: AlarmPermissionStatus = .unavailable
    private(set) var notificationSchedulingError: String?
    private(set) var alarmSchedulingError: String?

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
    private var alarmSchedulingTask: Task<Void, Never>?
    private var notificationSchedulingTask: Task<Void, Never>?
    private var isCatchingUpAfterLaunch = false
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
        // 一般通知在提醒建立時就先排好，前景與背景都交給系統呈現。
        refreshNotificationStatus()
        refreshAlarmPermissionStatus()

        isCatchingUpAfterLaunch = true
        tick()          // 補登 App 沒開著的期間響過的提醒
        isCatchingUpAfterLaunch = false
        synchronizePendingNotifications()
        synchronizeAlarms()
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
            let wasInBackground = wasDueWhileBackgrounded(fireDate: item.at)
            record(item.schedule, at: item.at, missed: wasInBackground)
            if !wasInBackground && !isScheduledSystemAlarm(item.schedule) {
                // 通知已授權時不再由 Timer 另外播一次。未授權時仍保留前景提示。
                let systemPlaysSound = !usesAlarmKit(for: item.schedule)
                    && notificationStatus == .authorized && notificationSoundsEnabled
                ring(item.schedule, at: item.at, playSound: !systemPlaysSound)
            }
        }
        persistEvents()
        // 前景也改由系統播放後，消耗一批通知時必須補入後續提醒，
        // 否則長時間開著 App 會在最初 58 則用完後停止響鈴。
        synchronizePendingNotifications()
    }

    /// 這一響是否發生在 App 不位於前景的期間？是的話回到前景就不補播，
    /// 但這不代表能確認使用者真的看見或聽見系統提醒。
    ///
    /// 冷啟動時，超過兩秒的舊時刻視為 App 未執行期間；一般前景計時器即使因主執行緒
    /// 暫時繁忙而延遲，也仍會補播。從背景回來時則依 `backgroundedAt` 判斷。
    private func wasDueWhileBackgrounded(fireDate: Date) -> Bool {
        if isCatchingUpAfterLaunch, Date().timeIntervalSince(fireDate) > 2 { return true }
        // 螢幕關掉、控制中心蓋著或來電時，`scenePhase` 只走到 `.inactive`，
        // `backgroundedAt` 還是空的。這時 App 自己播的鈴聲走的是媒體音量、
        // 畫面上的閃示也沒人看得到，響鈴必須讓給系統通知，否則兩邊都等於沒響。
        if !isVisiblyActive { return true }
        guard let backgroundedAt else { return false }
        return fireDate >= backgroundedAt.addingTimeInterval(-0.5)
    }

    /// App 是否真的在最前面、螢幕也亮著。
    ///
    /// 只控制 App 內的視覺提示與未授權時的前景播放，不再取消系統通知。
    private var isVisiblyActive: Bool {
        UIApplication.shared.applicationState == .active
    }

    private func isScheduledSystemAlarm(_ schedule: AlarmSchedule) -> Bool {
        guard usesAlarmKit(for: schedule), #available(iOS 26.0, *) else { return false }
        return AlarmKitScheduler.containsAlarm(id: schedule.id)
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

    private func ring(_ schedule: AlarmSchedule, at date: Date, playSound: Bool) {
        if playSound, let option = SoundCatalog.resolved(id: schedule.soundID) {
            SoundPlayer.shared.play(option, times: schedule.chimeCount)
        }
        if playSound { UINotificationFeedbackGenerator().notificationOccurred(.success) }

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
        requestRequiredPermissionIfNeeded(for: new)
        synchronizePendingNotifications()
        synchronizeAlarms(forceRescheduleIDs: [new.id])
    }

    func update(_ schedule: AlarmSchedule) {
        guard let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        var updated = schedule
        updated.cycleStart = nil        // 時刻可能改過了，這一輪重排
        schedules[index] = updated
        normalizeCycles()
        requestRequiredPermissionIfNeeded(for: updated)
        synchronizePendingNotifications(forceRescheduleIDs: [updated.id])
        synchronizeAlarms(forceRescheduleIDs: [updated.id])
    }

    func delete(_ schedule: AlarmSchedule) {
        schedules.removeAll { $0.id == schedule.id }
        synchronizePendingNotifications(forceRescheduleIDs: [schedule.id])
        synchronizeAlarms(forceRescheduleIDs: [schedule.id])
    }

    func delete(atOffsets offsets: IndexSet) {
        let removedIDs = Set(offsets.map { schedules[$0].id })
        schedules.remove(atOffsets: offsets)
        synchronizePendingNotifications(forceRescheduleIDs: removedIDs)
        synchronizeAlarms(forceRescheduleIDs: removedIDs)
    }

    func setEnabled(_ enabled: Bool, for schedule: AlarmSchedule) {
        guard let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        schedules[index].isEnabled = enabled
        schedules[index].cycleStart = nil
        normalizeCycles()
        if enabled {
            requestRequiredPermissionIfNeeded(for: schedules[index])
        }
        synchronizePendingNotifications(forceRescheduleIDs: [schedule.id])
        synchronizeAlarms(forceRescheduleIDs: [schedule.id])
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
            // 新安裝不應在使用者尚未操作前，自動啟用或排入任何提醒。
            return []
        }
        return decoded
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
            refreshNotificationStatus()
            refreshAlarmPermissionStatus()
            synchronizeAlarms()
            logDeliveredNotifications()
            tick()                      // 補登不在前景時響過的提醒
            synchronizePendingNotifications()
            backgroundedAt = nil
            startTicker()
        case .inactive:
            // 試聽或前景備援播放不應把 duckOthers 音訊工作階段帶進鎖定畫面。
            SoundPlayer.shared.stopAll()
        case .background:
            backgroundedAt = Date()
            scheduleBackgroundNotifications()
        default:
            break
        }
    }

    /// 回到 App 後讀取系統實際送達時間，包含鎖屏期間，不以倒數推算。
    private func logDeliveredNotifications() {
        Task {
            let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
            let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Stopwatch", category: "ReminderDelivery")
            for notification in delivered where notification.request.identifier.hasPrefix(NotificationID.reminder) {
                guard let timestamp = notification.request.identifier.split(separator: "-").last.flatMap({ Double($0) }) else { continue }
                let delay = notification.date.timeIntervalSince1970 - timestamp
                logger.info("System notification delivery delay: \(delay, privacy: .public) seconds")
            }
        }
    }

    // MARK: - 本地通知

    /// 在目前系統上，這組提醒是否應由 AlarmKit 送達。
    func usesAlarmKit(for schedule: AlarmSchedule) -> Bool {
        guard #available(iOS 26.0, *) else { return false }
        return schedule.hasAlarmSemantics
    }

    var hasEnabledNotificationSchedules: Bool {
        schedules.contains { $0.isEnabled && !usesAlarmKit(for: $0) }
    }

    var hasEnabledAlarmSchedules: Bool {
        schedules.contains { $0.isEnabled && usesAlarmKit(for: $0) }
    }

    private func requestRequiredPermissionIfNeeded(for schedule: AlarmSchedule) {
        guard schedule.isEnabled else { return }
        if usesAlarmKit(for: schedule) {
            requestAlarmPermissionIfNeeded()
        } else {
            requestNotificationPermissionIfNeeded()
        }
    }

    func requestNotificationPermissionIfNeeded() {
        // 不要 .badge：App 從來不設角標，多要一個權限只會讓授權對話框看起來更可疑。
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshNotificationStatus()
                self?.synchronizePendingNotifications()
            }
        }
    }

    func requestAlarmPermissionIfNeeded() {
        guard #available(iOS 26.0, *) else { return }
        Task {
            let state = await AlarmKitScheduler.requestAuthorization()
            alarmPermissionStatus = Self.permissionStatus(from: state)
            if state == .authorized {
                synchronizeAlarms()
            }
        }
    }

    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { [weak self] in
                self?.notificationStatus = settings.authorizationStatus
                // 只有 `.enabled` 才能當成已開啟。尤其暫時授權可能只把通知安靜
                // 放進通知中心；若用 `!= .disabled`，`.notSupported` 也會被誤判，畫面就會誤報
                // 一切正常，使用者卻看不到鎖定畫面也聽不到聲音。
                self?.notificationAlertsEnabled = settings.alertSetting == .enabled
                self?.notificationSoundsEnabled = settings.soundSetting == .enabled
                self?.notificationLockScreenEnabled = settings.lockScreenSetting == .enabled
                self?.notificationTimeSensitiveEnabled = settings.timeSensitiveSetting == .enabled
                self?.notificationScheduledDeliveryEnabled = settings.scheduledDeliverySetting == .enabled
                self?.notificationSettingsLoaded = true
            }
        }
    }

    func refreshAlarmPermissionStatus() {
        guard #available(iOS 26.0, *) else {
            alarmPermissionStatus = .unavailable
            return
        }
        alarmPermissionStatus = Self.permissionStatus(from: AlarmKitScheduler.authorizationState)
    }

    @available(iOS 26.0, *)
    private static func permissionStatus(
        from state: AlarmManager.AuthorizationState
    ) -> AlarmPermissionStatus {
        switch state {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        @unknown default: .denied
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

    /// 進背景時再次同步一般通知，並用背景任務等系統接收完成。
    private func scheduleBackgroundNotifications() {
        beginBackgroundTask()
        enqueuePendingNotificationSync(from: schedules) { [weak self] result in
            self?.recordNotificationSchedulingResult(result)
            self?.endBackgroundTask()
        }
    }

    /// 建立、修改、啟用提醒時就先交給通知中心，不把成功與否押在背景切換瞬間。
    private func synchronizePendingNotifications(forceRescheduleIDs: Set<UUID> = []) {
        enqueuePendingNotificationSync(
            from: schedules,
            forceRescheduleIDs: forceRescheduleIDs
        ) { [weak self] result in
            self?.recordNotificationSchedulingResult(result)
        }
    }

    private func recordNotificationSchedulingResult(_ result: NotificationSchedulingResult) {
        notificationSchedulingError = result.errors.first
    }

    /// AlarmKit 在使用者建立、修改或啟用鬧鐘時就持久同步，不依賴背景切換時機。
    private func synchronizeAlarms(forceRescheduleIDs: Set<UUID> = []) {
        guard #available(iOS 26.0, *) else { return }
        let alarmSchedules = schedules.filter { usesAlarmKit(for: $0) }
        let previousTask = alarmSchedulingTask
        alarmSchedulingTask = Task { [weak self] in
            await previousTask?.value
            let errors = await AlarmKitScheduler.synchronizeAlarms(
                with: alarmSchedules,
                forceRescheduleIDs: forceRescheduleIDs
            )
            self?.alarmSchedulingError = errors.first
        }
    }

    /// 把接下來的一般提醒排成本地通知（iOS 上限 64 則）。
    private func enqueuePendingNotificationSync(
        from sourceSchedules: [AlarmSchedule],
        forceRescheduleIDs: Set<UUID> = [],
        completion: @escaping (NotificationSchedulingResult) -> Void
    ) {
        let previousTask = notificationSchedulingTask
        notificationSchedulingTask = Task { [weak self] in
            await previousTask?.value
            guard let self else { return }
            // 音檔產生、通知提交與快取清理必須在同一序列，避免前一批刪除下一批音檔。
            let moment = Date()
            var upcoming: [(schedule: AlarmSchedule, at: Date)] = []
            for schedule in sourceSchedules where schedule.isEnabled && !usesAlarmKit(for: schedule) {
                guard let start = schedule.cycleStart else { continue }
                for date in schedule.upcomingFireDates(cycleStart: start,
                                                       after: moment,
                                                       limit: maxScheduledNotifications) {
                    upcoming.append((schedule, date))
                }
            }
            upcoming.sort { $0.at < $1.at }
            let batch = Array(upcoming.prefix(maxScheduledNotifications))
            // 這一輪真正被待送通知引用到的連響檔，等排程換完之後用來清掉其餘的舊快取。
            var referencedSoundNames: Set<String> = []
            let requests = batch.compactMap { item -> UNNotificationRequest? in
                let delay = item.at.timeIntervalSinceNow
                guard delay > 0 else { return nil }

                if let soundName = SoundCatalog.backgroundSoundName(for: item.schedule.soundID,
                                                                    times: item.schedule.chimeCount) {
                    referencedSoundNames.insert(soundName)
                }

                let identifier = "\(NotificationID.reminderPrefix(for: item.schedule.id))\(Int(item.at.timeIntervalSince1970))"

                let content = UNMutableNotificationContent()
                content.title = item.schedule.displayLabel
                content.body = TimeFormat.timeOfDayWithSeconds(item.at)
                content.interruptionLevel = .timeSensitive
                // 每一響有獨立識別碼；通知分組本身不決定是否播放聲音。
                content.threadIdentifier = identifier
                content.sound = SoundCatalog.notificationSound(
                    for: item.schedule.soundID,
                    times: item.schedule.chimeCount
                )

                return UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(
                        dateMatching: Calendar.current.dateComponents(
                            [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
                            from: item.at
                        ),
                        repeats: false
                    )
                )
            }

            let forceReplacePrefixes = Set(forceRescheduleIDs.map {
                NotificationID.reminderPrefix(for: $0)
            })
            let result = await LocalNotificationScheduler.shared.synchronizePending(
                withPrefix: NotificationID.reminder,
                requests: requests,
                forceReplacePrefixes: forceReplacePrefixes
            )
            // 同步失敗時可能仍有舊通知，保留其音檔以供系統讀取。
            if result.errors.isEmpty {
                SoundCatalog.pruneRepeatCache(keeping: referencedSoundNames)
            }
            completion(result)
        }
    }

}
