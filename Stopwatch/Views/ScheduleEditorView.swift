//
//  ScheduleEditorView.swift
//  Stopwatch
//

import SwiftUI

struct ScheduleEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var schedule: AlarmSchedule
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
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("標籤") {
                    TextField(schedule.defaultLabel, text: $schedule.label)
                }

                Section("提醒方式") {
                    Picker("方式", selection: $schedule.repeats) {
                        Text("重複").tag(true)
                        Text("單次").tag(false)
                    }
                    .pickerStyle(.segmented)

                    if schedule.repeats {
                        presetRow
                    }
                }

                Section {
                    DurationPicker(seconds: $schedule.firstFire)
                } header: {
                    Text("第一次響鈴")
                } footer: {
                    Text("碼表跑到 \(TimeFormat.clock(schedule.firstFire)) 時響第一次。")
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
                            Text("碼表超過 \(TimeFormat.clock(schedule.endAt)) 之後就不再響。")
                        } else {
                            Text("不設定的話會一直重複，直到你暫停或重置碼表。")
                        }
                    }
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

                    Stepper("連響次數：\(schedule.chimeCount)", value: $schedule.chimeCount, in: 1...5)

                    Button {
                        if let option = SoundCatalog.resolved(id: schedule.soundID) {
                            SoundPlayer.shared.play(option, times: schedule.chimeCount)
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
        if schedule.repeats && schedule.interval < 1 { return false }
        if schedule.firstFire < 1 { return false }
        return true
    }

    private var intervalFooter: String {
        guard schedule.interval >= 1 else { return "間隔至少要 1 秒。" }
        let times = (1...3).map { TimeFormat.clock(schedule.firstFire + Double($0) * schedule.interval) }
        return "接著會在 \(times.joined(separator: "、"))… 響。"
    }

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { minutes in
                    let seconds = TimeInterval(minutes * 60)
                    let selected = schedule.interval == seconds && schedule.firstFire == seconds
                    Button {
                        schedule.interval = seconds
                        schedule.firstFire = seconds
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
        result.firstFire = max(result.firstFire, 1)
        result.interval = max(result.interval, 1)
        if result.hasEnd {
            result.endAt = max(result.endAt, result.firstFire)
        }
        return result
    }
}
