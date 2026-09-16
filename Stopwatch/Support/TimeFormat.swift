//
//  TimeFormat.swift
//  Stopwatch
//

import SwiftUI

/// 時間字串格式化。
enum TimeFormat {

    /// 不含小數的長度：`05:23`，超過一小時變成 `1:05:23`
    static func clock(_ interval: TimeInterval) -> String {
        let total = Int(max(interval, 0).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// 一天當中的時刻：`14:30`（依使用者的 12／24 小時制設定）
    static func timeOfDay(hour: Int, minute: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1,
                                                              hour: hour, minute: minute))
        return date.map { timeOfDayFormatter.string(from: $0) } ?? "\(hour):\(minute)"
    }

    static func timeOfDay(_ date: Date) -> String {
        timeOfDayFormatter.string(from: date)
    }

    /// 含秒的時刻：`14:30:07`、`14:30:00`。
    ///
    /// 秒數剛好是 0 也一樣寫到秒。間隔不是整分鐘時（例如每 90 秒）響鈴會落在
    /// 半分鐘上，只寫到分鐘的話，連著兩筆紀錄會看起來是同一個時刻；而整分鐘的那幾筆
    /// 若省略 `:00`，同一份清單裡的時刻長短不一，反而更難對照。
    static func timeOfDayWithSeconds(_ date: Date) -> String {
        withSecondsFormatter.string(from: date)
    }

    private static let withSecondsFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("j:mm:ss")
        return formatter
    }()

    /// 快到了就寫倒數（`還有 04:25`），還很久就直接寫時刻 —— 一小時以上的倒數讀不出意思。
    static func countdownOrTime(to date: Date, from now: Date) -> String {
        let remaining = date.timeIntervalSince(now)
        guard remaining < 3600 else { return dayQualified(date, from: now) }
        return "還有 \(clock(max(remaining, 0)))"
    }

    /// 不是今天的話要把日子寫出來。
    ///
    /// 設定時刻若已經過了，這一輪會自動排到隔天；只寫「21:25」會讓人以為它早就過期不響了。
    static func dayQualified(_ date: Date, from now: Date = Date()) -> String {
        let calendar = Calendar.current
        let time = timeOfDay(date)
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<1: return time
        case 1: return "明天 \(time)"
        default: return "\(dayFormatter.string(from: date)) \(time)"
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
    }()

    private static let timeOfDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("j:mm")
        return formatter
    }()

    /// 人類可讀的長度：`1 小時 5 分 30 秒`
    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(max(interval, 0).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) 小時") }
        if minutes > 0 { parts.append("\(minutes) 分") }
        if seconds > 0 || parts.isEmpty { parts.append("\(seconds) 秒") }
        return parts.joined(separator: " ")
    }
}

/// 排程用的顏色標記。
enum Palette {
    static let colors: [Color] = [
        .orange, .blue, .green, .pink, .purple, .teal, .red, .indigo,
    ]

    static func color(at index: Int) -> Color {
        let count = colors.count
        return colors[((index % count) + count) % count]
    }
}
