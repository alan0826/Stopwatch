//
//  TimeFormat.swift
//  Stopwatch
//

import SwiftUI

/// 碼表相關的時間字串格式化。
enum TimeFormat {

    /// 碼表主顯示：`05:23.41`，超過一小時變成 `1:05:23.41`
    static func stopwatch(_ interval: TimeInterval) -> String {
        let total = max(interval, 0)
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        let seconds = Int(total) % 60
        let centiseconds = Int((total - total.rounded(.down)) * 100)

        if hours > 0 {
            return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds)
        }
        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
    }

    /// 不含小數的時間點：`05:23`，超過一小時變成 `1:05:23`
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
