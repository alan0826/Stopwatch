//
//  ReminderMetadata.swift
//  Stopwatch
//
//  App 與 Widget Extension 共用。
//

import AlarmKit
import Foundation

/// 隨系統鬧鐘一起帶著走的資料，讓 Widget Extension 認得是哪一組提醒。
///
/// AlarmKit 的警示畫面是由 ActivityKit 呈現的，而 `AlarmAttributes<Metadata>`
/// 必須在 App 與 Widget Extension 兩邊都是「同一個型別」才配得起來，
/// 因此這個檔案同時編進兩個 target，不能只放在其中一邊。
@available(iOS 26.0, *)
struct ReminderMetadata: AlarmMetadata {
    let scheduleID: UUID

    init(scheduleID: UUID) {
        self.scheduleID = scheduleID
    }
}
