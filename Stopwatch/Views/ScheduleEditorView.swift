//
//  ScheduleEditorView.swift
//  Stopwatch
//

import SwiftUI

struct ScheduleEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var schedule: AlarmSchedule
    /// `DatePicker` 要的是 `Date`，存的則是時／分兩個數字。
    @State private var firstTime: Date
    /// 開啟時帶進來的那一份，只拿來比對是不是同一個編輯頁，見檔尾的 `Equatable`。
    private let original: AlarmSchedule
    private let isNew: Bool
    private let onSave: (AlarmSchedule) -> Void
    private let onDelete: (() -> Void)?

    /// 重複間隔的快速選項（分鐘）
    private let presets = [1, 3, 5, 10, 15, 30, 60]

    init(schedule: AlarmSchedule,
         isNew: Bool = false,
         onSave: @escaping (AlarmSchedule) -> Void,
         onDelete: (() -> Void)? = nil) {
        _schedule = State(initialValue: schedule)
        _firstTime = State(initialValue: Calendar.current.date(
            from: DateComponents(year: 2001, month: 1, day: 1,
                                 hour: schedule.firstHour, minute: schedule.firstMinute)) ?? Date())
        self.original = schedule
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                // 響完一輪的提醒會自動關閉。少了這個開關，使用者改好時刻按儲存之後
                // 提醒仍然是關著的，等於怎麼改都不會再響。
                if !isNew {
                    Section {
                        Toggle("啟用這組提醒", isOn: $schedule.isEnabled)
                    } footer: {
                        Text(schedule.isEnabled
                             ? "關閉之後就不會再響。"
                             : "這組提醒目前是關著的，開啟之後才會依下面的設定響。")
                    }
                }

                Section("標籤") {
                    TextField(schedule.defaultLabel, text: $schedule.label)
                }

                Section {
                    Picker("方式", selection: $schedule.repeats) {
                        Text("重複").tag(true)
                        Text("單次").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: schedule.repeats) { _, repeats in
                        // 間隔循環不是鬧鐘語意，不能保留 AlarmKit 模式。
                        if repeats { schedule.usesSystemAlarm = false }
                    }

                    if schedule.repeats {
                        presetRow
                    }
                } header: {
                    Text("提醒方式")
                } footer: {
                    if #available(iOS 26.0, *) {
                        Text(schedule.repeats
                             ? "間隔循環在背景時使用系統通知，不保證突破靜音或專注模式。"
                             : "單次預設為一般提醒，播完指定連響次數後會自動結束。")
                    } else {
                        Text("背景與鎖定螢幕時由系統通知送達。")
                    }
                }

                if !schedule.repeats {
                    Section {
                        Toggle("持續響鈴直到停止", isOn: $schedule.usesSystemAlarm)
                            .disabled(!systemAlarmAvailable)
                    } header: {
                        Text("系統鬧鐘")
                    } footer: {
                        if systemAlarmAvailable {
                            Text(schedule.usesSystemAlarm
                                 ? "使用 iOS 26 的 AlarmKit，會突破靜音與專注模式，並持續響鈴，直到你在鎖定畫面或系統鬧鐘上按下停止。"
                                 : "關閉時會依連響次數播放後自動結束，但不保證突破靜音或專注模式。")
                        } else {
                            Text("「持續響鈴直到停止」需要 iOS 26 或更新版本。目前系統會以一般本地通知送達這組提醒。")
                        }
                    }
                }

                Section {
                    DatePicker("時刻", selection: $firstTime, displayedComponents: .hourAndMinute)
                } header: {
                    Text("第一次響鈴")
                } footer: {
                    Text(firstFireFooter)
                }

                if schedule.repeats {
                    Section {
                        DurationPicker(seconds: $schedule.interval)
                    } header: {
                        Text("重複間隔")
                    } footer: {
                        Text(intervalFooter)
                    }

                    Section {
                        Toggle("設定結束時間", isOn: $schedule.hasEnd)
                        if schedule.hasEnd {
                            DurationPicker(seconds: $schedule.endAt)
                        }
                    } footer: {
                        if schedule.hasEnd {
                            Text("第一次響鈴之後再過 \(TimeFormat.duration(schedule.endAt)) 就不再響。")
                        } else {
                            Text("不設定的話會一直重複，直到你把這組提醒關掉。")
                        }
                    }

                }

                Section {
                    Toggle("每天重複", isOn: $schedule.repeatsDaily)
                        .onChange(of: schedule.repeatsDaily) { _, on in
                            // 會重複又沒有結束時間的話，這一輪永遠跑不完，也就輪不到隔天。
                            if on, schedule.repeats { schedule.hasEnd = true }
                        }
                } footer: {
                    Text(dailyFooter)
                }

                Section("鈴聲") {
                    NavigationLink {
                        SoundPickerView(soundID: $schedule.soundID)
                    } label: {
                        HStack {
                            Text("鈴聲")
                            Spacer()
                            Text(soundName)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if schedule.hasAlarmSemantics {
                        Text("系統鬧鐘會持續響到手動停止，不使用連響次數。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Stepper("連響次數：\(schedule.chimeCount)",
                                value: $schedule.chimeCount,
                                in: 1...5)
                    }

                    Button {
                        if let option = SoundCatalog.resolved(id: schedule.soundID) {
                            SoundPlayer.shared.play(
                                option,
                                times: schedule.hasAlarmSemantics ? 1 : schedule.chimeCount
                            )
                        }
                    } label: {
                        Label("試聽", systemImage: "play.circle")
                    }
                }

                Section("顏色") {
                    colorRow
                }

                if !isNew, onDelete != nil {
                    Section {
                        Button(role: .destructive) {
                            onDelete?()
                            dismiss()
                        } label: {
                            Text("刪除這組提醒")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "新增提醒" : "編輯提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        onSave(normalized())
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private var soundName: String {
        SoundCatalog.resolved(id: schedule.soundID)?.name ?? "預設"
    }

    private var isValid: Bool {
        !(schedule.repeats && schedule.interval < 1)
    }

    private var systemAlarmAvailable: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    /// 設定的時刻若今天已經過了，這一輪會排到明天 —— 要寫出來，
    /// 否則使用者只看到一個早就過去的時刻，會以為提醒壞了。
    private var firstFireFooter: String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: firstTime)
        var probe = AlarmSchedule()
        probe.firstHour = parts.hour ?? 0
        probe.firstMinute = parts.minute ?? 0
        guard let next = probe.firstFireDate(onOrAfter: Date()) else {
            return "時鐘走到 \(TimeFormat.timeOfDay(firstTime)) 時響第一次。"
        }
        return "時鐘走到 \(TimeFormat.dayQualified(next)) 時響第一次。"
    }

    private var dailyFooter: String {
        guard schedule.repeatsDaily else {
            return "只跑這一輪，響完就自動關閉。"
        }
        let time = TimeFormat.timeOfDay(firstTime)
        return schedule.repeats
            ? "一輪響完之後，隔天 \(time) 再來一輪。需要設定結束時間，這一輪才有結束的時候。"
            : "每天 \(time) 響一次。"
    }

    private var intervalFooter: String {
        guard schedule.interval >= 1 else { return "間隔至少要 1 秒。" }
        // 直接列出接下來幾次的時刻，比只寫間隔直觀。
        let times = (1...3).map {
            TimeFormat.timeOfDay(firstTime.addingTimeInterval(Double($0) * schedule.interval))
        }
        return "接著會在 \(times.joined(separator: "、"))… 響。"
    }

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { minutes in
                    let seconds = TimeInterval(minutes * 60)
                    let selected = schedule.interval == seconds
                    Button {
                        schedule.interval = seconds
                    } label: {
                        Text("每 \(minutes) 分")
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(selected ? Color.accentColor : Color(.tertiarySystemFill))
                            )
                            .foregroundStyle(selected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var colorRow: some View {
        HStack(spacing: 12) {
            ForEach(0..<Palette.colors.count, id: \.self) { index in
                Circle()
                    .fill(Palette.color(at: index))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle()
                            .stroke(Color.primary, lineWidth: schedule.colorIndex == index ? 2 : 0)
                    )
                    .onTapGesture { schedule.colorIndex = index }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func normalized() -> AlarmSchedule {
        var result = schedule
        let parts = Calendar.current.dateComponents([.hour, .minute], from: firstTime)
        result.firstHour = parts.hour ?? result.firstHour
        result.firstMinute = parts.minute ?? result.firstMinute
        result.interval = max(result.interval, 1)
        if !systemAlarmAvailable {
            result.usesSystemAlarm = false
        }
        if result.hasEnd {
            result.endAt = max(result.endAt, result.interval)
        }
        return result
    }
}

/// 主畫面的時鐘每秒走一格，開著的編輯頁也跟著每秒重算一次。重算剛好碰上注音組字
/// 還沒選字的時候，標籤欄位已經打的注音會被直接送出成文字，變成「ㄐ」加上一段新的組字。
///
/// 兩個閉包沒辦法比對，SwiftUI 只好每次都當成新的畫面。這裡明講：帶進來的是同一份
/// 排程就算同一個編輯頁，呼叫端再加上 `.equatable()`，時鐘的更新就不會傳進來。
extension ScheduleEditorView: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.original == rhs.original && lhs.isNew == rhs.isNew
    }
}
