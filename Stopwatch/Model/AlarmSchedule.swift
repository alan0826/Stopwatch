//
//  AlarmSchedule.swift
//  Stopwatch
//

import Foundation

/// 一組提醒排程。
///
/// 第一次響鈴是**時鐘時刻**（例如 14:30）；碼表就在那一刻從 0 開始跑，
/// 之後的重複與結束時間都以「碼表已跑的秒數」為基準。
/// 多組排程可以同時存在、互相疊加，共用同一個碼表時間軸。
struct AlarmSchedule: Identifiable, Codable, Hashable {
    var id = UUID()
    /// 顯示用標籤，例如「每 5 分鐘」
    var label = ""
    var isEnabled = true

    /// 第一次響鈴的時鐘時刻
    var firstHour = 9
    var firstMinute = 0

    /// 是否重複
    var repeats = true
    /// 重複間隔（秒）
    var interval: TimeInterval = 300
    /// 是否有結束時間
    var hasEnd = false
    /// 停止重複的碼表秒數（從第一次響鈴起算）
    var endAt: TimeInterval = 3600
    /// 一輪跑完之後，隔天同一個時刻再來一輪。
    /// 需要搭配結束時間，否則這一輪永遠不會結束，也就輪不到隔天。
    var repeatsDaily = false

    /// 鈴聲識別碼，對應 `SoundCatalog`
    var soundID = SoundCatalog.defaultID
    /// 每次提醒連響幾聲
    var chimeCount = 1
    var colorIndex = 0

    init() {}

    /// 每個欄位都用「有就讀、沒有就用預設值」，這樣之後再加欄位時，
    /// 舊的存檔不會整份解不開，使用者的排程也就不會被清掉。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AlarmSchedule()

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? fallback.id
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? fallback.label
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? fallback.isEnabled
        firstHour = try container.decodeIfPresent(Int.self, forKey: .firstHour) ?? fallback.firstHour
        firstMinute = try container.decodeIfPresent(Int.self, forKey: .firstMinute) ?? fallback.firstMinute
        repeats = try container.decodeIfPresent(Bool.self, forKey: .repeats) ?? fallback.repeats
        interval = try container.decodeIfPresent(TimeInterval.self, forKey: .interval) ?? fallback.interval
        hasEnd = try container.decodeIfPresent(Bool.self, forKey: .hasEnd) ?? fallback.hasEnd
        endAt = try container.decodeIfPresent(TimeInterval.self, forKey: .endAt) ?? fallback.endAt
        repeatsDaily = try container.decodeIfPresent(Bool.self, forKey: .repeatsDaily) ?? fallback.repeatsDaily
        soundID = try container.decodeIfPresent(String.self, forKey: .soundID) ?? fallback.soundID
        chimeCount = try container.decodeIfPresent(Int.self, forKey: .chimeCount) ?? fallback.chimeCount
        colorIndex = try container.decodeIfPresent(Int.self, forKey: .colorIndex) ?? fallback.colorIndex
    }

    /// 新排程的預設時刻：往後推到下一個 5 分整。
    ///
    /// 至少留 2 分鐘的餘裕 —— 預設值若只差幾十秒，使用者還在設定的時候那個時刻就過了，
    /// 存檔之後會被安靜地排到隔天。
    static func makeNew(after now: Date = Date()) -> AlarmSchedule {
        var schedule = AlarmSchedule()
        let calendar = Calendar.current
        let lead = now.addingTimeInterval(120)
        let minute = calendar.component(.minute, from: lead)
        let target = calendar.date(byAdding: .minute, value: (5 - minute % 5) % 5, to: lead) ?? lead

        let parts = calendar.dateComponents([.hour, .minute], from: target)
        schedule.firstHour = parts.hour ?? schedule.firstHour
        schedule.firstMinute = parts.minute ?? schedule.firstMinute
        return schedule
    }

    var firstTimeText: String {
        TimeFormat.timeOfDay(hour: firstHour, minute: firstMinute)
    }

    var displayLabel: String {
        label.trimmingCharacters(in: .whitespaces).isEmpty ? defaultLabel : label
    }

    var defaultLabel: String {
        repeats ? "每 \(TimeFormat.duration(interval))" : "\(firstTimeText) 提醒"
    }

    /// 排程摘要，例如「14:30 第一次 · 每 5 分 · 到 30:00 為止」
    var summary: String {
        var parts = ["\(firstTimeText) 第一次"]
        if repeats {
            parts.append("每 \(TimeFormat.duration(interval))")
            if hasEnd { parts.append("持續 \(TimeFormat.duration(endAt))") }
        } else {
            parts.append("單次")
        }
        if repeatsDaily { parts.append("每天") }
        return parts.joined(separator: " · ")
    }

    // MARK: - 第一次響鈴

    /// `date` 之後（含當下這一秒）最近一次符合設定時刻的絕對時間。
    func firstFireDate(onOrAfter date: Date) -> Date? {
        Calendar.current.nextDate(after: date.addingTimeInterval(-1),
                                  matching: DateComponents(hour: firstHour, minute: firstMinute),
                                  matchingPolicy: .nextTime)
    }

    /// 這組排程在碼表時間軸上的第一次響鈴秒數。
    ///
    /// 碼表從 `stopwatchStart` 開始跑，所以「比碼表起跑還早的時刻」要算到隔天，
    /// 這正是 `firstFireDate(onOrAfter:)` 的行為。
    func firstFireElapsed(stopwatchStart: Date) -> TimeInterval {
        guard let date = firstFireDate(onOrAfter: stopwatchStart) else { return 0 }
        return max(date.timeIntervalSince(stopwatchStart), 0)
    }

    // MARK: - 響鈴時間計算

    /// 這組排程在 `(from, through]` 這段碼表區間內所有的響鈴時間點。
    func fireTimes(firstFire: TimeInterval,
                   after from: TimeInterval,
                   through upperBound: TimeInterval) -> [TimeInterval] {
        guard isEnabled, upperBound > from else { return [] }

        guard repeats, interval >= 1 else {
            return (firstFire > from && firstFire <= upperBound) ? [firstFire] : []
        }

        let limit = hasEnd ? min(upperBound, firstFire + endAt) : upperBound
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
    func upcomingFireTimes(firstFire: TimeInterval,
                           after time: TimeInterval,
                           limit: Int) -> [TimeInterval] {
        guard isEnabled, limit > 0 else { return [] }

        guard repeats, interval >= 1 else {
            return firstFire > time ? [firstFire] : []
        }

        var times: [TimeInterval] = []
        var step = max(0, Int(((time - firstFire) / interval).rounded(.down)) + 1)
        while times.count < limit {
            let fire = firstFire + Double(step) * interval
            if hasEnd, fire > firstFire + endAt { break }
            if fire > time { times.append(fire) }
            step += 1
        }
        return times
    }
}

/// 已經響過的一次提醒紀錄。
struct FireEvent: Identifiable, Hashable, Codable {
    var id = UUID()
    var scheduleID: UUID
    var label: String
    /// 響鈴時碼表的秒數
    var at: TimeInterval
    /// 響鈴時的實際時刻，跨越好幾輪之後這個才讀得出意思
    var firedAt: Date
    var colorIndex: Int
    /// true 代表 App 當時在背景，由系統通知送達（回到前景才補登紀錄）
    var deliveredInBackground: Bool
}
