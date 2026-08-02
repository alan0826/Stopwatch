//
//  NotificationIdentifier.swift
//  Stopwatch
//

import UserNotifications

/// 提醒通知的識別碼前綴，讓 App 只清理自己排的那一批。
enum NotificationID {
    static let reminder = "reminder-"
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
    /// `completion` 會等到整批都排完才呼叫，讓呼叫端可以用背景任務把時間撐住。
    func replacePending(withPrefix prefix: String,
                        using build: @escaping () -> [UNNotificationRequest],
                        completion: (() -> Void)? = nil) {
        getPendingNotificationRequests { requests in
            let stale = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            if !stale.isEmpty {
                self.removePendingNotificationRequests(withIdentifiers: stale)
            }
            DispatchQueue.main.async {
                let batch = build()
                guard !batch.isEmpty else {
                    completion?()
                    return
                }
                let group = DispatchGroup()
                for request in batch {
                    group.enter()
                    self.add(request) { _ in group.leave() }
                }
                group.notify(queue: .main) { completion?() }
            }
        }
    }
}
