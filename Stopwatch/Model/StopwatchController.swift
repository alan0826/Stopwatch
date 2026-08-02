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
            guard schedules != oldValue else { return }
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
        let at: TimeInterval
    }

    // MARK: - 設定

    /// 碼表執行時不讓螢幕自動鎖定。
    var keepScreenOn: Bool {
        didSet {
            UserDefaults.standard.set(keepScreenOn, forKey: Keys.keepScreenOn)
            applyIdleTimer()
        }
    }

    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - 內部狀態

    private enum Keys {
        static let schedules = "schedules.v1"
        static let keepScreenOn = "settings.keepScreenOn"
    }

    private var ticker: Timer?
    private var lastCheckedElapsed: TimeInterval = 0
    private var flashResetWorkItem: DispatchWorkItem?

    /// 本地通知一次最多只會保留 64 則，這裡預留一些空間。
    private let maxScheduledNotifications = 58

    init() {
        let defaults = UserDefaults.standard
        keepScreenOn = defaults.object(forKey: Keys.keepScreenOn) as? Bool ?? true
        schedules = Self.loadSchedules()
    }

    // MARK: - 碼表控制

    func toggleRunning() {
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning else { return }
        startedAt = Date()
        isRunning = true
        lastCheckedElapsed = accumulated
        displayNow = Date()

        startTicker()
        applyIdleTimer()
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
    }

    func reset() {
        stopTicker()
        isRunning = false
        startedAt = nil
        accumulated = 0
        lastCheckedElapsed = 0
        displayNow = Date()
        events.removeAll()
        flash = nil

        SoundPlayer.shared.stopAll()
        cancelPendingNotifications()
        applyIdleTimer()
    }

    // MARK: - 計時器

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
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
        guard isRunning else { return }

        let now = preciseElapsed
        fireDueAlarms(from: lastCheckedElapsed, to: now)
        lastCheckedElapsed = now
    }

    // MARK: - 響鈴

    private func fireDueAlarms(from: TimeInterval, to now: TimeInterval) {
        guard now > from else { return }

        var due: [(schedule: AlarmSchedule, time: TimeInterval)] = []
        for schedule in schedules where schedule.isEnabled {
            for time in schedule.fireTimes(after: from, through: now) {
                due.append((schedule, time))
            }
        }
        guard !due.isEmpty else { return }
        due.sort { $0.time < $1.time }

        for item in due {
            // 落後超過 1.5 秒代表 App 剛剛在背景（聲音已由通知送出），這裡只補登紀錄。
            let missed = (now - item.time) > 1.5
            record(item.schedule, at: item.time, missed: missed)
            if !missed {
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

    // MARK: - 下一次提醒

    /// 所有排程中最接近的下一次響鈴。
    var nextFire: (schedule: AlarmSchedule, time: TimeInterval)? {
        let now = elapsed
        var best: (schedule: AlarmSchedule, time: TimeInterval)?
        for schedule in schedules where schedule.isEnabled {
            guard let time = schedule.nextFireTime(after: now) else { continue }
            if best == nil || time < best!.time {
                best = (schedule, time)
            }
        }
        return best
    }

    func nextFireTime(for schedule: AlarmSchedule) -> TimeInterval? {
        schedule.nextFireTime(after: elapsed)
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
        var schedule = AlarmSchedule()
        schedule.label = "每 5 分鐘"
        schedule.firstFire = 300
        schedule.interval = 300
        schedule.repeats = true
        return schedule
    }

    // MARK: - 背景行為

    private func applyIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn && isRunning
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            displayNow = Date()
            cancelPendingNotifications()
            refreshNotificationStatus()
            if isRunning { tick() }   // 補登在背景期間響過的提醒
        case .background:
            if isRunning {
                scheduleBackgroundNotifications()
            }
        default:
            break
        }
    }

    // MARK: - 本地通知

    func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] _, _ in
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

    /// 進背景時，把接下來的響鈴時間點排成本地通知（iOS 上限 64 則）。
    private func scheduleBackgroundNotifications() {
        let now = preciseElapsed
        var upcoming: [(schedule: AlarmSchedule, time: TimeInterval)] = []
        for schedule in schedules where schedule.isEnabled {
            for time in schedule.upcomingFireTimes(after: now, limit: maxScheduledNotifications) {
                upcoming.append((schedule, time))
            }
        }
        upcoming.sort { $0.time < $1.time }
        let batch = Array(upcoming.prefix(maxScheduledNotifications))

        // 只換掉自己的通知，鬧鐘與計時器排的不受影響。
        UNUserNotificationCenter.current().replacePending(withPrefix: NotificationID.reminder) {
            batch.compactMap { item in
                let delay = item.time - now
                guard delay > 0.5 else { return nil }

                let content = UNMutableNotificationContent()
                content.title = item.schedule.displayLabel
                content.body = "碼表 \(TimeFormat.clock(item.time))"
                content.interruptionLevel = .timeSensitive
                content.sound = Self.notificationSound(for: item.schedule)

                return UNNotificationRequest(
                    identifier: "\(NotificationID.reminder)\(item.schedule.id.uuidString)-\(Int(item.time.rounded()))",
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                )
            }
        }
    }

    private static func notificationSound(for schedule: AlarmSchedule) -> UNNotificationSound {
        AlarmStore.notificationSound(for: schedule.soundID)
    }

    private func cancelPendingNotifications() {
        UNUserNotificationCenter.current().removePending(withPrefix: NotificationID.reminder)
    }
}
