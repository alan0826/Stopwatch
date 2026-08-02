//
//  CountdownTimer.swift
//  Stopwatch
//

import Foundation
import Observation
import UserNotifications

/// 內建時鐘那種倒數計時器。
@Observable
final class CountdownTimer {

    /// 使用者在滾輪上選的長度。
    var duration: TimeInterval = 300
    var label = ""
    var soundID = SoundCatalog.defaultID {
        didSet { UserDefaults.standard.set(soundID, forKey: Keys.sound) }
    }

    private(set) var isRunning = false
    private(set) var displayNow = Date()
    private(set) var recents: [TimeInterval] = []

    private var endDate: Date?
    private var pausedRemaining: TimeInterval?
    private var totalDuration: TimeInterval = 0
    private var ticker: Timer?

    private enum Keys {
        static let recents = "timer.recents"
        static let sound = "timer.sound"
    }

    init() {
        recents = UserDefaults.standard.array(forKey: Keys.recents) as? [TimeInterval] ?? []
        soundID = UserDefaults.standard.string(forKey: Keys.sound) ?? SoundCatalog.defaultID
    }

    // MARK: - 狀態

    /// 已經開始（執行中或暫停中）。
    var isActive: Bool { endDate != nil || pausedRemaining != nil }

    var remaining: TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return duration }
        return max(endDate.timeIntervalSince(displayNow), 0)
    }

    var progress: Double {
        guard totalDuration > 0 else { return 1 }
        return min(max(remaining / totalDuration, 0), 1)
    }

    /// 結束的時刻，例如「09:41」。
    var endTimeText: String {
        let date = endDate ?? Date().addingTimeInterval(remaining)
        return Self.clockFormatter.string(from: date)
    }

    var canStart: Bool { duration >= 1 }

    // MARK: - 控制

    func start() {
        guard canStart else { return }
        totalDuration = duration
        endDate = Date().addingTimeInterval(duration)
        pausedRemaining = nil
        isRunning = true
        displayNow = Date()

        rememberRecent(duration)
        startTicker()
        scheduleNotification(after: duration)
    }

    func pause() {
        guard isRunning else { return }
        pausedRemaining = remaining
        endDate = nil
        isRunning = false
        stopTicker()
        cancelNotification()
    }

    func resume() {
        guard let pausedRemaining, !isRunning else { return }
        endDate = Date().addingTimeInterval(pausedRemaining)
        self.pausedRemaining = nil
        isRunning = true
        displayNow = Date()
        startTicker()
        scheduleNotification(after: pausedRemaining)
    }

    func cancel() {
        stopTicker()
        isRunning = false
        endDate = nil
        pausedRemaining = nil
        totalDuration = 0
        displayNow = Date()
        cancelNotification()
    }

    func startRecent(_ seconds: TimeInterval) {
        duration = seconds
        start()
    }

    // MARK: - 計時

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 1.0 / 10.0, repeats: true) { [weak self] _ in
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
        displayNow = Date()
        guard isRunning, let endDate else { return }
        if endDate.timeIntervalSinceNow <= 0 {
            finish()
        }
    }

    private func finish() {
        stopTicker()
        isRunning = false
        self.endDate = nil
        pausedRemaining = nil
        totalDuration = 0

        if let option = SoundCatalog.resolved(id: soundID) {
            SoundPlayer.shared.play(option, times: 3)
        }
    }

    /// 回到前景時補算：在背景期間如果已經到點，就把狀態收乾淨。
    func refresh() {
        displayNow = Date()
        if isRunning, let endDate, endDate.timeIntervalSinceNow <= 0 {
            stopTicker()
            isRunning = false
            self.endDate = nil
            totalDuration = 0
        }
    }

    // MARK: - 最近使用

    private func rememberRecent(_ seconds: TimeInterval) {
        var updated = recents.filter { $0 != seconds }
        updated.insert(seconds, at: 0)
        recents = Array(updated.prefix(6))
        UserDefaults.standard.set(recents, forKey: Keys.recents)
    }

    // MARK: - 通知

    private func scheduleNotification(after seconds: TimeInterval) {
        guard seconds > 0.5 else { return }
        let content = UNMutableNotificationContent()
        content.title = label.trimmingCharacters(in: .whitespaces).isEmpty ? "計時器" : label
        content.body = "時間到"
        content.interruptionLevel = .timeSensitive
        content.sound = AlarmStore.notificationSound(for: soundID)

        let request = UNNotificationRequest(
            identifier: NotificationID.timerCurrent,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [NotificationID.timerCurrent])
        center.add(request)
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [NotificationID.timerCurrent])
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("j:mm")
        return formatter
    }()
}
