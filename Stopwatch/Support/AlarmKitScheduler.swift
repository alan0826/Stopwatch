//
//  AlarmKitScheduler.swift
//  Stopwatch
//

import ActivityKit
import AlarmKit
import Foundation
import SwiftUI

/// iOS 26 的系統鬧鐘排程。
///
/// 鬧鐘在使用者建立或修改時就交給系統持久管理；App 不依賴背景切換瞬間才排程。
@available(iOS 26.0, *)
@MainActor
enum AlarmKitScheduler {

    static var authorizationState: AlarmManager.AuthorizationState {
        AlarmManager.shared.authorizationState
    }

    static func containsAlarm(id: UUID) -> Bool {
        (try? AlarmManager.shared.alarms.contains { $0.id == id }) ?? false
    }

    static func requestAuthorization() async -> AlarmManager.AuthorizationState {
        do {
            return try await AlarmManager.shared.requestAuthorization()
        } catch {
            return AlarmManager.shared.authorizationState
        }
    }

    /// 讓 AlarmKit 內的鬧鐘與 App 資料一致。
    ///
    /// 已存在且內容沒被使用者修改的鬧鐘會保留，避免每次場景切換都全數取消重建，
    /// 造成 AlarmKit 明明回報成功、到點卻沒有進入 alerting 的不穩定情況。
    @discardableResult
    static func synchronizeAlarms(
        with schedules: [AlarmSchedule],
        forceRescheduleIDs: Set<UUID> = []
    ) async -> [String] {
        guard authorizationState == .authorized else { return [] }

        var errors: [String] = []
        let desired = Dictionary(uniqueKeysWithValues: schedules
            .filter { $0.isEnabled && $0.hasAlarmSemantics }
            .map { ($0.id, $0) })

        let existing: [Alarm]
        do {
            existing = try AlarmManager.shared.alarms
        } catch {
            return ["無法讀取系統鬧鐘：\(error.localizedDescription)"]
        }

        var existingIDs = Set(existing.map(\.id))
        for alarm in existing where desired[alarm.id] == nil || forceRescheduleIDs.contains(alarm.id) {
            // 單次到點後 UI 會自動關閉開關，但正在響的鬧鐘要等使用者停止。
            if alarm.state == .alerting, !forceRescheduleIDs.contains(alarm.id) { continue }
            do {
                try AlarmManager.shared.cancel(id: alarm.id)
                existingIDs.remove(alarm.id)
            } catch {
                errors.append("無法更新系統鬧鐘：\(error.localizedDescription)")
            }
        }

        for schedule in desired.values where !existingIDs.contains(schedule.id) {
            guard !Task.isCancelled else { break }
            guard let configuration = configuration(for: schedule) else {
                // 設定時刻已經過了才來排，系統會拒收。安靜跳過的話使用者只會看到
                // 一組開著卻永遠不響的鬧鐘，所以要把原因說出來。
                errors.append("\(schedule.displayLabel)：響鈴時刻已經過了，請重新設定時刻。")
                continue
            }
            do {
                _ = try await AlarmManager.shared.schedule(id: schedule.id,
                                                           configuration: configuration)
                if Task.isCancelled {
                    try? AlarmManager.shared.cancel(id: schedule.id)
                    break
                }
            } catch {
                errors.append("\(schedule.displayLabel)：\(error.localizedDescription)")
                continue
            }
        }
        return errors
    }

    private static func configuration(
        for schedule: AlarmSchedule
    ) -> AlarmManager.AlarmConfiguration<ReminderMetadata>? {
        guard let cycleStart = schedule.cycleStart else { return nil }

        let alarmSchedule: Alarm.Schedule
        if schedule.repeatsDaily {
            let everyDay: [Locale.Weekday] = [
                .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday,
            ]
            let time = Alarm.Schedule.Relative.Time(hour: schedule.firstHour,
                                                    minute: schedule.firstMinute)
            alarmSchedule = .relative(.init(time: time, repeats: .weekly(everyDay)))
        } else {
            guard cycleStart > Date() else { return nil }
            alarmSchedule = .fixed(cycleStart)
        }

        let title = LocalizedStringResource(stringLiteral: schedule.displayLabel)
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title)
        } else {
            let stopButton = AlarmButton(text: "停止",
                                         textColor: .white,
                                         systemImageName: "stop.circle")
            alert = AlarmPresentation.Alert(title: title, stopButton: stopButton)
        }

        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: ReminderMetadata(scheduleID: schedule.id),
            tintColor: Palette.color(at: schedule.colorIndex)
        )
        // AlarmKit 會持續維持鬧鐘警示直到使用者停止，不套用「連響次數」。
        let soundName = SoundCatalog.backgroundSoundName(for: schedule.soundID, times: 1)
        let sound = soundName.map(AlertConfiguration.AlertSound.named) ?? .default

        return .alarm(schedule: alarmSchedule,
                      attributes: attributes,
                      sound: sound)
    }
}
