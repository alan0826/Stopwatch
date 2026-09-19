//
//  AlarmSchedule.swift
//  Stopwatch
//

import Foundation

/// 一組提醒排程。
///
/// 時間全部以時鐘為準：第一次響鈴是某個時刻（例如 14:30），之後每隔 `interval` 響一次，
/// 距離第一次超過 `endAt` 就結束這一輪。設了「每天重複」就隔天同一時刻再來一輪，
/// 沒設的話跑完就把自己關掉。
struct AlarmSchedule: Identifiable, Codable, Hashable {
    var id = UUID()
    /// 顯示用標籤，例如「每 5 分鐘」
    var label = ""
    var isEnabled = true

    /// 第一次響鈴的時刻
    var firstHour = 9
    var firstMinute = 0

    /// 是否重複
    var repeats = true
    /// 重複間隔（秒）
    var interval: TimeInterval = 300
    /// 是否有結束時間
    var hasEnd = false
    /// 距離第一次響鈴多久之後就不再響（秒）
    var endAt: TimeInterval = 3600
    /// 一輪跑完之後，隔天同一個時刻再來一輪。
    var repeatsDaily = false

    /// iOS 26 以上是否使用會持續響到手動停止的系統鬧鐘。
    /// 一般單次提醒預設為 false，播完 `chimeCount` 後自動結束。
    var usesSystemAlarm = false

    /// 鈴聲識別碼，對應 `SoundCatalog`
    var soundID = SoundCatalog.defaultID
    /// 每次提醒連響幾聲
    var chimeCount = 1
    var colorIndex = 0

    /// 這一輪第一次響鈴的絕對時刻。
    ///
    /// 啟用時決定，跑完之後換到隔天或直接關掉。存起來是因為使用者多半會關掉 App
    /// 等它響，回來時得知道「這一輪是從哪個時刻算起的」，而不是重新算成明天。
    var cycleStart: Date?

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
        usesSystemAlarm = try container.decodeIfPresent(Bool.self, forKey: .usesSystemAlarm)
            ?? fallback.usesSystemAlarm
        soundID = try container.decodeIfPresent(String.self, forKey: .soundID) ?? fallback.soundID
        chimeCount = try container.decodeIfPresent(Int.self, forKey: .chimeCount) ?? fallback.chimeCount
        colorIndex = try container.decodeIfPresent(Int.self, forKey: .colorIndex) ?? fallback.colorIndex
        cycleStart = try container.decodeIfPresent(Date.self, forKey: .cycleStart)
    }

    /// 新排程的預設時刻：往後推到下一個 5 分整。
    ///
    /// 至少留 2 分鐘的餘裕 —— 預設值若只差幾十秒，使用者還在設定的時候那個時刻就過了，
    /// 存檔之後會被安靜地排到隔天。
    static func makeNew(colorIndex: Int = 0, after now: Date = Date()) -> AlarmSchedule {
        var schedule = AlarmSchedule()
        schedule.colorIndex = colorIndex
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

    /// 排程摘要，例如「14:30 第一次 · 每 5 分 · 持續 1 小時 · 每天」
    var summary: String {
        var parts = ["\(firstTimeText) 第一次"]
        if repeats {
            parts.append("每 \(TimeFormat.duration(interval))")
            if hasEnd { parts.append("持續 \(TimeFormat.duration(endAt))") }
        } else {
            parts.append("單次")
        }
        if repeatsDaily { parts.append("每天") }
        if hasAlarmSemantics { parts.append("持續響到停止") }
        return parts.joined(separator: " · ")
    }

    /// AlarmKit 只用在使用者明確選擇「持續響到停止」的單次／每日鬧鐘。
    ///
    /// 「每 N 秒／分鐘」的區間循環是一般提醒，不應為了突破靜音與專注模式
    /// 而全部包裝成系統鬧鐘。實際是否能用 AlarmKit 仍由 iOS 版本決定。
    ///
    /// 同時要求系統支援：iOS 18 上沒有 AlarmKit，這種排程只能退回一般通知，
    /// 摘要與編輯畫面若還宣稱「持續響到停止」就是在騙人。
    var hasAlarmSemantics: Bool {
        guard !repeats, usesSystemAlarm else { return false }
        if #available(iOS 26.0, *) { return true }
        return false
    }

    // MARK: - 響鈴時刻

    /// `date` 之後（含當下這一秒）最近一次符合設定時刻的絕對時間。
    func firstFireDate(onOrAfter date: Date) -> Date? {
        Calendar.current.nextDate(after: date.addingTimeInterval(-1),
                                  matching: DateComponents(hour: firstHour, minute: firstMinute),
                                  matchingPolicy: .nextTime)
    }

    /// 這一輪最後一次響鈴的時刻。`nil` 代表沒有盡頭（重複但沒設結束時間）。
    private func cycleEnd(from start: Date) -> Date? {
        guard repeats, interval >= 1 else { return start }
        guard hasEnd else { return nil }
        let steps = (endAt / interval).rounded(.down)
        return start.addingTimeInterval(steps * interval)
    }

    /// 這一輪在 `(after, through]` 之間的所有響鈴時刻。
    func fireDates(cycleStart start: Date, after: Date, through: Date) -> [Date] {
        guard isEnabled, through > after else { return [] }

        guard repeats, interval >= 1 else {
            return (start > after && start <= through) ? [start] : []
        }

        let last = cycleEnd(from: start)
        var result: [Date] = []
        var step = max(0, Int((after.timeIntervalSince(start) / interval).rounded(.down)) + 1)
        while result.count < 2000 {
            let fire = start.addingTimeInterval(Double(step) * interval)
            if let last, fire > last { break }
            if fire > through { break }
            if fire > after { result.append(fire) }
            step += 1
        }
        return result
    }

    /// 這一輪在 `date` 之後的下一次響鈴。`nil` 代表這一輪跑完了。
    func nextFireDate(cycleStart start: Date, after date: Date) -> Date? {
        guard isEnabled else { return nil }

        guard repeats, interval >= 1 else {
            return start > date ? start : nil
        }

        let last = cycleEnd(from: start)
        var step = max(0, Int((date.timeIntervalSince(start) / interval).rounded(.down)) + 1)
        while step < 100_000 {
            let fire = start.addingTimeInterval(Double(step) * interval)
            if let last, fire > last { return nil }
            if fire > date { return fire }
            step += 1
        }
        return nil
    }

    /// `date` 之後接下來幾次響鈴。設了「每天重複」就會跨到之後的每一輪。
    func upcomingFireDates(cycleStart start: Date, after date: Date, limit: Int) -> [Date] {
        guard isEnabled, limit > 0 else { return [] }

        var result: [Date] = []
        var cycle = start
        var cursor = date
        var extraCycles = 0

        while result.count < limit, extraCycles <= 60 {
            if let next = nextFireDate(cycleStart: cycle, after: cursor) {
                result.append(next)
                cursor = next
                continue
            }
            // 這一輪沒了，看看要不要接到隔天那一輪。
            guard repeatsDaily,
                  let nextCycle = Calendar.current.date(byAdding: .day, value: 1, to: cycle)
            else { break }
            cycle = nextCycle
            cursor = cycle.addingTimeInterval(-1)
            extraCycles += 1
        }
        return result
    }
}

/// 已經響過的一次提醒紀錄。
struct FireEvent: Identifiable, Hashable, Codable {
    var id = UUID()
    var scheduleID: UUID
    var label: String
    /// 響鈴的實際時刻
    var firedAt: Date
    var colorIndex: Int
    /// true 只代表該時刻 App 不在前景；系統是否真的顯示或播放提醒無法由 App 回推。
    var deliveredInBackground: Bool
}
