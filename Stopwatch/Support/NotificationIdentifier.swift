//
//  NotificationIdentifier.swift
//  Stopwatch
//

import UserNotifications

/// 各功能的通知識別碼前綴，讓彼此可以獨立排程與取消，不會互相清掉。
enum NotificationID {
    static let reminder = "reminder-"
    static let alarm = "alarm-"
    static let timer = "timer-"

    static let timerCurrent = timer + "current"

    static let alarmCategory = "ALARM_CATEGORY"
    static let snoozeAction = "ALARM_SNOOZE"
    static let stopAction = "ALARM_STOP"

    /// 稍後提醒的間隔，與系統鬧鐘一致。
    static let snoozeInterval: TimeInterval = 9 * 60
}

extension UNUserNotificationCenter {

    /// 移除指定前綴的待送通知。
    func removePending(withPrefix prefix: String) {
        getPendingNotificationRequests { requests in
            let stale = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            guard !stale.isEmpty else { return }
            self.removePendingNotificationRequests(withIdentifiers: stale)
        }
    }

    /// 先移除指定前綴的舊通知，再排入新的一批。
    /// 兩個步驟串在同一條回呼上，避免新排的通知被前一次的清除動作誤刪。
    func replacePending(withPrefix prefix: String, using build: @escaping () -> [UNNotificationRequest]) {
        getPendingNotificationRequests { requests in
            let stale = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            if !stale.isEmpty {
                self.removePendingNotificationRequests(withIdentifiers: stale)
            }
            DispatchQueue.main.async {
                for request in build() {
                    self.add(request)
                }
            }
        }
    }
}
