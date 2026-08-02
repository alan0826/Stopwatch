//
//  AlarmStore.swift
//  Stopwatch
//

import Foundation
import Observation
import SwiftUI
import UserNotifications

/// 鬧鐘清單，內容變動時自動重新排入本地通知。
@Observable
final class AlarmStore {

    var alarms: [WallClockAlarm] = [] {
        didSet {
            guard alarms != oldValue else { return }
            persist()
            reschedule()
        }
    }

    private static let storageKey = "alarms.v1"

    init() {
        alarms = Self.load()
    }

    // MARK: - 編輯

    func add(_ alarm: WallClockAlarm) {
        alarms.append(alarm)
        sort()
    }

    func update(_ alarm: WallClockAlarm) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        alarms[index] = alarm
        sort()
    }

    func delete(_ alarm: WallClockAlarm) {
        alarms.removeAll { $0.id == alarm.id }
    }

    func delete(atOffsets offsets: IndexSet) {
        alarms.remove(atOffsets: offsets)
    }

    func setEnabled(_ enabled: Bool, for alarm: WallClockAlarm) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        alarms[index].isEnabled = enabled
    }

    private func sort() {
        alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    // MARK: - 排程

    func reschedule() {
        let snapshot = alarms
        UNUserNotificationCenter.current().replacePending(withPrefix: NotificationID.alarm) {
            snapshot.filter(\.isEnabled).flatMap { Self.requests(for: $0) }
        }
    }

    private static func requests(for alarm: WallClockAlarm) -> [UNNotificationRequest] {
        let content = UNMutableNotificationContent()
        content.title = alarm.displayLabel
        content.body = alarm.timeText
        content.interruptionLevel = .timeSensitive
        content.sound = notificationSound(for: alarm.soundID)
        if alarm.snoozeEnabled {
            content.categoryIdentifier = NotificationID.alarmCategory
        }

        if alarm.repeatDays.isEmpty {
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: alarm.hour, minute: alarm.minute),
                repeats: false
            )
            return [UNNotificationRequest(identifier: "\(NotificationID.alarm)\(alarm.id.uuidString)",
                                          content: content,
                                          trigger: trigger)]
        }

        return alarm.repeatDays.sorted().map { weekday in
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: alarm.hour, minute: alarm.minute, weekday: weekday),
                repeats: true
            )
            return UNNotificationRequest(identifier: "\(NotificationID.alarm)\(alarm.id.uuidString)-\(weekday)",
                                         content: content,
                                         trigger: trigger)
        }
    }

    static func notificationSound(for soundID: String) -> UNNotificationSound {
        guard let option = SoundCatalog.resolved(id: soundID),
              let name = SoundCatalog.notificationSoundName(for: option) else {
            return .default
        }
        return UNNotificationSound(named: UNNotificationSoundName(name))
    }

    // MARK: - 儲存

    private func persist() {
        guard let data = try? JSONEncoder().encode(alarms) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func load() -> [WallClockAlarm] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([WallClockAlarm].self, from: data) else {
            return []
        }
        return decoded
    }
}
