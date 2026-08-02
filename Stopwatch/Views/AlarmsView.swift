//
//  AlarmsView.swift
//  Stopwatch
//

import SwiftUI

struct AlarmsView: View {
    @Environment(AlarmStore.self) private var store

    @State private var editingAlarm: WallClockAlarm?
    @State private var draftAlarm: WallClockAlarm?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                NotificationPermissionBanner()

                if store.alarms.isEmpty {
                    Spacer()
                    ContentUnavailableView("沒有鬧鐘", systemImage: "alarm",
                                           description: Text("點右上角的 ＋ 加入一個鬧鐘。"))
                    Spacer()
                } else {
                    List {
                        Section("其他") {
                            ForEach(store.alarms) { alarm in
                                AlarmRow(alarm: alarm) { enabled in
                                    store.setEnabled(enabled, for: alarm)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { editingAlarm = alarm }
                            }
                            .onDelete { store.delete(atOffsets: $0) }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("鬧鐘")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !store.alarms.isEmpty { EditButton() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        draftAlarm = WallClockAlarm()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("加入鬧鐘")
                }
            }
            .sheet(item: $editingAlarm) { alarm in
                AlarmEditorView(alarm: alarm) { updated in
                    store.update(updated)
                } onDelete: {
                    store.delete(alarm)
                }
            }
            .sheet(item: $draftAlarm) { alarm in
                AlarmEditorView(alarm: alarm, isNew: true) { created in
                    store.add(created)
                }
            }
        }
    }
}

private struct AlarmRow: View {
    let alarm: WallClockAlarm
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(alarm.timeText)
                    .font(.system(size: 44, weight: .thin, design: .rounded))
                    .monospacedDigit()
                Text(alarm.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(alarm.isEnabled ? Color.primary : Color.secondary)

            Spacer()

            Toggle("", isOn: Binding(get: { alarm.isEnabled }, set: onToggle))
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}
