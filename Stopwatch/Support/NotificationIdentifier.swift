//
//  NotificationIdentifier.swift
//  Stopwatch
//

import UserNotifications

/// 提醒通知的識別碼前綴，讓 App 只清理自己排的那一批。
enum NotificationID {
    nonisolated static let reminder = "reminder-"

    /// 到點後給系統完成交付的空間；使用者主動刪除或修改不適用此保留。
    nonisolated static func isAwaitingDelivery(_ identifier: String, at moment: Date) -> Bool {
        guard identifier.hasPrefix(reminder),
              let timestamp = identifier.split(separator: "-").last.flatMap({ Double($0) })
        else { return false }
        return (0...120).contains(moment.timeIntervalSince1970 - timestamp)
    }

    /// 通知識別碼帶版本，讓新版排程邏輯第一次啟動時能淘汰舊請求。
    static func reminderPrefix(for scheduleID: UUID) -> String {
        "\(reminder)v3-\(scheduleID.uuidString)-"
    }
}

struct NotificationSchedulingResult {
    let scheduledCount: Int
    let errors: [String]
}

/// 讓待送通知逐筆對齊目前排程，並把整個過程串成單一序列。
///
/// 已經正確存在的通知必須保留。若每次切換前景／背景都先整批刪除再重排，
/// 使用者剛好在提醒前鎖定螢幕時，最近那一響會落在「已刪除、尚未補回」的空窗而漏掉。
actor LocalNotificationScheduler {

    static let shared = LocalNotificationScheduler()

    private let center = UNUserNotificationCenter.current()

    func synchronizePending(
        withPrefix prefix: String,
        requests: [UNNotificationRequest],
        forceReplacePrefixes: Set<String> = []
    ) async -> NotificationSchedulingResult {
        let desiredByIdentifier = Dictionary(
            uniqueKeysWithValues: requests.map { ($0.identifier, $0) }
        )
        let pending = await center.pendingNotificationRequests()
        let managed = pending.filter { $0.identifier.hasPrefix(prefix) }

        let moment = Date()
        let stale = managed.compactMap { request -> String? in
            let isForced = forceReplacePrefixes.contains {
                request.identifier.hasPrefix($0)
            }
            if isForced {
                // 同 ID 的更新交給 add 原子替換，避免先刪後加造成空窗。
                return desiredByIdentifier[request.identifier] == nil ? request.identifier : nil
            }
            if desiredByIdentifier[request.identifier] != nil { return nil }
            // 到點不代表已送達；保留短暫交付中的請求，避免 Timer 或鎖屏同步撤回它。
            if NotificationID.isAwaitingDelivery(request.identifier, at: moment) {
                return nil
            }
            return request.identifier
        }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }

        let keptIdentifiers = Set(managed.map(\.identifier)).subtracting(stale)
        let missing = requests.filter { request in
            !keptIdentifiers.contains(request.identifier)
                || forceReplacePrefixes.contains { request.identifier.hasPrefix($0) }
        }

        var errors: [String] = []
        for request in missing {
            do {
                try await center.add(request)
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        let verifiedRequests = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(prefix) }
        let verified = verifiedRequests.count
        let verifiedIDs = Set(verifiedRequests.map(\.identifier))

        // 已到點的請求可能正交付，不把它當作排程失敗；逐一查核未來請求，
        // 避免保留的到點通知數量掩蓋新請求沒有排入的問題。
        let verificationTime = Date().timeIntervalSince1970
        let futureRequests = requests.filter { request in
            guard let timestamp = request.identifier.split(separator: "-").last.flatMap({ Double($0) }) else { return true }
            return timestamp > verificationTime
        }
        let acceptedFutureCount = futureRequests.filter { verifiedIDs.contains($0.identifier) }.count
        let status = await center.notificationSettings().authorizationStatus
        let canSchedule = status == .authorized || status == .provisional || status == .ephemeral
        if errors.isEmpty, canSchedule, acceptedFutureCount < futureRequests.count {
            errors.append("系統只接受 \(acceptedFutureCount)／\(futureRequests.count) 則待送通知。")
        }
        return NotificationSchedulingResult(scheduledCount: verified, errors: errors)
    }
}
