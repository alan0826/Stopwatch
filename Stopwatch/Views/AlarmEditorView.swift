//
//  AlarmEditorView.swift
//  Stopwatch
//

import SwiftUI

struct AlarmEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var alarm: WallClockAlarm
    @State private var time: Date

    private let isNew: Bool
    private let onSave: (WallClockAlarm) -> Void
    private let onDelete: (() -> Void)?

    init(alarm: WallClockAlarm,
         isNew: Bool = false,
         onSave: @escaping (WallClockAlarm) -> Void,
         onDelete: (() -> Void)? = nil) {
        _alarm = State(initialValue: alarm)
        _time = State(initialValue: alarm.time)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)

                Section {
                    NavigationLink {
                        RepeatPicker(days: $alarm.repeatDays)
                    } label: {
                        LabeledContent("重複", value: alarm.repeatText)
                    }

                    HStack {
                        Text("標籤")
                        Spacer()
                        TextField("鬧鐘", text: $alarm.label)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        SoundPickerView(soundID: $alarm.soundID)
                    } label: {
                        LabeledContent("鈴聲", value: SoundCatalog.resolved(id: alarm.soundID)?.name ?? "預設")
                    }

                    Toggle("稍後提醒", isOn: $alarm.snoozeEnabled)
                }

                if !isNew, onDelete != nil {
                    Section {
                        Button(role: .destructive) {
                            onDelete?()
                            dismiss()
                        } label: {
                            Text("刪除鬧鐘")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "加入鬧鐘" : "編輯鬧鐘")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        var result = alarm
                        result.setTime(from: time)
                        result.isEnabled = true
                        onSave(result)
                        dismiss()
                    }
                }
            }
        }
    }
}

/// 重複的星期選擇。
private struct RepeatPicker: View {
    @Binding var days: Set<Int>

    var body: some View {
        List {
            ForEach(1...7, id: \.self) { weekday in
                Button {
                    if days.contains(weekday) {
                        days.remove(weekday)
                    } else {
                        days.insert(weekday)
                    }
                } label: {
                    HStack {
                        Text("每\(WallClockAlarm.weekdayNames[weekday - 1])")
                            .foregroundStyle(Color.primary)
                        Spacer()
                        if days.contains(weekday) {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("重複")
        .navigationBarTitleDisplayMode(.inline)
    }
}
