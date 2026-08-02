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

    private(set) var alarms: [WallClockAlarm] = []

    private static let storageKey = "alarms.v1"

    init() {
        alarms = Self.load()
    }

    // MARK: - 編輯

    func add(_ alarm: WallClockAlarm) {
        commit(alarms + [alarm])
    }

    func update(_ alarm: WallClockAlarm) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        var updated = alarms
        updated[index] = alarm
        // 時刻可能被改過，預定的響鈴時間要重算。
        updated[index].oneTimeFireDate = nil
        commit(updated)
    }

    func delete(_ alarm: WallClockAlarm) {
        commit(alarms.filter { $0.id != alarm.id })
    }

    func delete(atOffsets offsets: IndexSet) {
        var updated = alarms
        updated.remove(atOffsets: offsets)
        commit(updated)
    }

    func setEnabled(_ enabled: Bool, for alarm: WallClockAlarm) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        var updated = alarms
        updated[index].isEnabled = enabled
        // 重新打開時要重算下一次，不能沿用上次已經過期的時刻。
        updated[index].oneTimeFireDate = nil
        commit(updated)
    }

    /// App 啟動或回到前景時呼叫：把已經響過的一次性鬧鐘關掉，並重新排入通知。
    func refresh() {
        commit(alarms)
    }

    /// 所有變動都走這裡：正規化 → 存檔 → 重排通知。
    private func commit(_ updated: [WallClockAlarm]) {
        var next = updated
        Self.retireElapsedOneTimeAlarms(&next, now: Date())
        next.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }

        // 存檔只在真的有變動時做；重排則每次都做，開 App 時才有機會補回系統掉的通知。
        if next != alarms {
            alarms = next
            persist()
        }
        reschedule()
    }

    /// 一次性鬧鐘響過就自動關閉；還沒排定的就補上預定時刻。重複的鬧鐘不受影響。
    private static func retireElapsedOneTimeAlarms(_ alarms: inout [WallClockAlarm], now: Date) {
        for index in alarms.indices {
            guard alarms[index].repeatDays.isEmpty, alarms[index].isEnabled else {
                alarms[index].oneTimeFireDate = nil
                continue
            }
            guard let fireDate = alarms[index].oneTimeFireDate else {
                alarms[index].oneTimeFireDate = alarms[index].nextOccurrence(after: now)
                continue
            }
            if fireDate <= now {
                alarms[index].isEnabled = false
                alarms[index].oneTimeFireDate = nil
            }
        }
    }

    // MARK: - 排程

    private func reschedule() {
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
