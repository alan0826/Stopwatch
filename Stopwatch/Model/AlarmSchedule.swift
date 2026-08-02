//
//  AlarmSchedule.swift
//  Stopwatch
//

import Foundation

/// 一組提醒排程。時間全部以「碼表已跑的秒數」為基準，
/// 多組排程可以同時存在、互相疊加。
struct AlarmSchedule: Identifiable, Codable, Hashable {
    var id = UUID()
    /// 顯示用標籤，例如「每 5 分鐘」
    var label = ""
    var isEnabled = true

    /// 第一次響鈴的碼表秒數
    var firstFire: TimeInterval = 300
    /// 是否重複
    var repeats = true
    /// 重複間隔（秒）
    var interval: TimeInterval = 300
    /// 是否有結束時間
    var hasEnd = false
    /// 停止重複的碼表秒數
    var endAt: TimeInterval = 3600

    /// 鈴聲識別碼，對應 `SoundCatalog`
    var soundID = SoundCatalog.defaultID
    /// 每次提醒連響幾聲
    var chimeCount = 1
    var colorIndex = 0

    var displayLabel: String {
        label.trimmingCharacters(in: .whitespaces).isEmpty ? defaultLabel : label
    }

    var defaultLabel: String {
        repeats ? "每 \(TimeFormat.duration(interval))" : "\(TimeFormat.clock(firstFire)) 提醒"
    }

    /// 排程摘要，例如「01:00 開始 · 每 5 分 · 到 30:00 為止」
    var summary: String {
        var parts = ["\(TimeFormat.clock(firstFire)) 第一次"]
        if repeats {
            parts.append("每 \(TimeFormat.duration(interval))")
            if hasEnd { parts.append("到 \(TimeFormat.clock(endAt)) 為止") }
        } else {
            parts.append("單次")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 響鈴時間計算

    /// 這組排程在 `(from, through]` 這段碼表區間內所有的響鈴時間點。
    func fireTimes(after from: TimeInterval, through upperBound: TimeInterval) -> [TimeInterval] {
        guard isEnabled, upperBound > from else { return [] }

        guard repeats, interval >= 1 else {
            return (firstFire > from && firstFire <= upperBound) ? [firstFire] : []
        }

        let limit = hasEnd ? min(upperBound, endAt) : upperBound
        guard limit >= firstFire else { return [] }

        var times: [TimeInterval] = []
        var step = max(0, Int(((from - firstFire) / interval).rounded(.down)) + 1)
        while times.count < 2000 {
            let time = firstFire + Double(step) * interval
            if time > limit { break }
            if time > from { times.append(time) }
            step += 1
        }
        return times
    }

    /// 碼表跑到 `time` 之後，接下來的幾次響鈴時間點。
    func upcomingFireTimes(after time: TimeInterval, limit: Int) -> [TimeInterval] {
        guard isEnabled, limit > 0 else { return [] }

        guard repeats, interval >= 1 else {
            return firstFire > time ? [firstFire] : []
        }

        var times: [TimeInterval] = []
        var step = max(0, Int(((time - firstFire) / interval).rounded(.down)) + 1)
        while times.count < limit {
            let fire = firstFire + Double(step) * interval
            if hasEnd, fire > endAt { break }
            if fire > time { times.append(fire) }
            step += 1
        }
        return times
    }

    func nextFireTime(after time: TimeInterval) -> TimeInterval? {
        upcomingFireTimes(after: time, limit: 1).first
    }
}

/// 已經響過的一次提醒紀錄。
struct FireEvent: Identifiable, Hashable {
    let id = UUID()
    let scheduleID: UUID
    let label: String
    let at: TimeInterval
    let colorIndex: Int
    /// true 代表 App 當時在背景，由系統通知送達（回到前景才補登紀錄）
    let deliveredInBackground: Bool
}
