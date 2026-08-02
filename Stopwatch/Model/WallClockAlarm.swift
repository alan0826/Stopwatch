//
//  WallClockAlarm.swift
//  Stopwatch
//

import Foundation

/// 一般時鐘鬧鐘：在每天的某個時刻響。
struct WallClockAlarm: Identifiable, Codable, Hashable {
    var id = UUID()
    var hour = 7
    var minute = 0
    var label = "鬧鐘"
    /// `Calendar` 的 weekday：1 = 週日 … 7 = 週六
    var repeatDays: Set<Int> = []
    var soundID = SoundCatalog.defaultID
    var snoozeEnabled = true
    var isEnabled = true

    static let weekdayNames = ["週日", "週一", "週二", "週三", "週四", "週五", "週六"]

    /// 只帶時間的 `Date`，給 `DatePicker` 使用。
    var time: Date {
        Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1,
                                                   hour: hour, minute: minute)) ?? Date()
    }

    mutating func setTime(from date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        hour = components.hour ?? 0
        minute = components.minute ?? 0
    }

    var timeText: String {
        Self.timeFormatter.string(from: time)
    }

    var repeatText: String {
        Self.repeatText(for: repeatDays)
    }

    var displayLabel: String {
        label.trimmingCharacters(in: .whitespaces).isEmpty ? "鬧鐘" : label
    }

    var subtitle: String {
        repeatDays.isEmpty ? displayLabel : "\(displayLabel)，\(repeatText)"
    }

    static func repeatText(for days: Set<Int>) -> String {
        if days.isEmpty { return "永不" }
        if days.count == 7 { return "每天" }
        if days == [2, 3, 4, 5, 6] { return "平日" }
        if days == [1, 7] { return "週末" }
        return days.sorted().map { weekdayNames[$0 - 1] }.joined(separator: " ")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("j:mm")
        return formatter
    }()
}
