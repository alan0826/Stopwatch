//
//  StopAlarmIntent.swift
//  Stopwatch
//
//  App 與 Widget Extension 共用。
//

import AlarmKit
import AppIntents
import Foundation

/// 鎖定畫面／動態島上的「停止」。
///
/// LiveActivityIntent 由主 App 行程執行；主 App 與 Widget 都必須編入型別。
@available(iOS 26.0, *)
struct StopAlarmIntent: LiveActivityIntent {

    static let title: LocalizedStringResource = "停止提醒"
    static let isDiscoverable: Bool = false

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {
        alarmID = ""
    }

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            try AlarmManager.shared.stop(id: id)
        }
        return .result()
    }
}
