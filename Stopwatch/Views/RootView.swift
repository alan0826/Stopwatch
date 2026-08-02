//
//  RootView.swift
//  Stopwatch
//

import SwiftUI

struct RootView: View {
    @Environment(StopwatchController.self) private var controller

    @State private var editingSchedule: AlarmSchedule?
    @State private var draftSchedule: AlarmSchedule?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                NotificationPermissionBanner()

                List {
                Section {
                    timerCard
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    controls
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                schedulesSection
                historySection
                }
                .listStyle(.insetGrouped)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("循環提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        draftSchedule = newSchedule()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新增提醒")
                }
            }
            .sheet(item: $editingSchedule) { schedule in
                ScheduleEditorView(schedule: schedule) { updated in
                    controller.update(updated)
                } onDelete: {
                    controller.delete(schedule)
                }
            }
            .sheet(item: $draftSchedule) { schedule in
                ScheduleEditorView(schedule: schedule, isNew: true) { created in
                    controller.addSchedule(created)
                }
            }
            .overlay(alignment: .top) {
                flashBanner
            }
            .animation(.spring(duration: 0.35), value: controller.flash)
        }
    }

    // MARK: - 碼表

    private var timerCard: some View {
        VStack(spacing: 10) {
            Text(TimeFormat.stopwatch(controller.elapsed))
                .font(.system(size: 62, weight: .light, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(controller.isRunning ? Color.primary : Color.secondary)

            nextFireLine
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private var nextFireLine: some View {
        if let armed = controller.armedFirstFire {
            HStack(spacing: 6) {
                Circle()
                    .fill(Palette.color(at: armed.schedule.colorIndex))
                    .frame(width: 8, height: 8)
                Text("\(TimeFormat.timeOfDay(armed.date)) 響第一次 · 碼表同時起跑")
            }
        } else if let next = controller.nextFire {
            let remaining = max(next.time - controller.elapsed, 0)
            HStack(spacing: 6) {
                Circle()
                    .fill(Palette.color(at: next.schedule.colorIndex))
                    .frame(width: 8, height: 8)
                Text("下一次 \(next.schedule.displayLabel) · 還有 \(TimeFormat.clock(remaining))")
                    .monospacedDigit()
            }
        } else if controller.schedules.contains(where: { $0.isEnabled }) {
            Text("所有提醒都已響完")
        } else {
            Text("尚未設定提醒")
        }
    }

    private var controls: some View {
        HStack(spacing: 44) {
            controlButton(title: "重置", tint: .gray) {
                controller.reset()
            }
            .disabled(!controller.isRunning && controller.elapsed == 0)

            controlButton(title: controller.isRunning ? "暫停" : "開始",
                          tint: controller.isRunning ? .orange : .green) {
                controller.toggleRunning()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func controlButton(title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.title3.weight(.medium))
                .frame(width: 84, height: 84)
                .background(Circle().fill(tint.opacity(0.18)))
                .overlay(Circle().stroke(tint.opacity(0.35), lineWidth: 1.5))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 排程

    private var schedulesSection: some View {
        Section("提醒排程") {
            if controller.schedules.isEmpty {
                emptyState
            } else {
                ForEach(controller.schedules) { schedule in
                    ScheduleRow(schedule: schedule,
                                nextFire: controller.nextFireTime(for: schedule),
                                nextFireDate: controller.nextFireDate(for: schedule),
                                elapsed: controller.elapsed,
                                isWaiting: controller.armedFirstFire != nil,
                                firedCount: controller.firedCount(for: schedule),
                                onTap: { editingSchedule = schedule },
                                onToggle: { controller.setEnabled($0, for: schedule) })
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            controller.delete(schedule)
                        } label: {
                            Label("刪除", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            controller.preview(schedule)
                        } label: {
                            Label("試聽", systemImage: "speaker.wave.2.fill")
                        }
                        .tint(.blue)
                    }
                }
                .onDelete { controller.delete(atOffsets: $0) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell.badge")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("還沒有任何提醒")
                .font(.headline)
            Text("例如加一組「每 5 分鐘」，碼表跑到 5:00、10:00、15:00… 都會響一次。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("新增提醒") { draftSchedule = newSchedule() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - 紀錄

    @ViewBuilder
    private var historySection: some View {
        if !controller.events.isEmpty {
            Section("提醒紀錄") {
                ForEach(controller.events.prefix(30)) { event in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Palette.color(at: event.colorIndex))
                            .frame(width: 8, height: 8)
                        Text(event.label)
                        Spacer()
                        if event.deliveredInBackground {
                            Image(systemName: "bell.badge.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("由背景通知送達")
                        }
                        Text(TimeFormat.timeOfDay(event.firedAt))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    // MARK: - 響鈴提示

    @ViewBuilder
    private var flashBanner: some View {
        if let flash = controller.flash {
            HStack(spacing: 12) {
                Image(systemName: "bell.fill")
                    .font(.title3)
                    .foregroundStyle(Palette.color(at: flash.colorIndex))
                VStack(alignment: .leading, spacing: 2) {
                    Text(flash.label)
                        .font(.headline)
                    Text("碼表 \(TimeFormat.clock(flash.at))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Palette.color(at: flash.colorIndex).opacity(0.6), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: -

    private func newSchedule() -> AlarmSchedule {
        var schedule = AlarmSchedule.makeNew()
        schedule.colorIndex = controller.schedules.count
        return schedule
    }
}

// MARK: - 排程列

private struct ScheduleRow: View {
    let schedule: AlarmSchedule
    let nextFire: TimeInterval?
    let nextFireDate: Date?
    let elapsed: TimeInterval
    /// 還在等第一次響鈴：這時候顯示時鐘時刻比顯示碼表倒數有意義。
    let isWaiting: Bool
    let firedCount: Int
    let onTap: () -> Void
    let onToggle: (Bool) -> Void

    private var soundName: String {
        SoundCatalog.resolved(id: schedule.soundID)?.name ?? "預設"
    }

    var body: some View {
        HStack(spacing: 12) {
            // 開關必須留在可點擊區域之外：整列都吃點擊的話，點開關會變成打開編輯頁，
            // 而編輯頁裡並沒有啟用／停用的選項，等於整個關不掉。
            content
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)

            Toggle("", isOn: Binding(get: { schedule.isEnabled }, set: onToggle))
                .labelsHidden()
        }
        .padding(.vertical, 4)
        .opacity(schedule.isEnabled ? 1 : 0.55)
    }

    private var content: some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(Palette.color(at: schedule.colorIndex))
                .frame(width: 4, height: 40)
                .opacity(schedule.isEnabled ? 1 : 0.3)

            VStack(alignment: .leading, spacing: 3) {
                Text(schedule.displayLabel)
                    .font(.body.weight(.medium))
                Text(schedule.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Image(systemName: "speaker.wave.2.fill")
                        .accessibilityHidden(true)
                    Text(soundName)
                    if schedule.chimeCount > 1 {
                        Text("× \(schedule.chimeCount)")
                    }
                    if firedCount > 0 {
                        Text("· 已響 \(firedCount) 次")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if schedule.isEnabled, isWaiting {
                Text(schedule.firstTimeText)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.color(at: schedule.colorIndex))
            } else if schedule.isEnabled, let nextFire {
                // 還要等一小時以上就直接寫時刻，不然會出現「23:53:42」這種讀不出意思的倒數。
                let remaining = max(nextFire - elapsed, 0)
                Text(remaining >= 3600 && nextFireDate != nil
                     ? TimeFormat.timeOfDay(nextFireDate!)
                     : TimeFormat.clock(remaining))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.color(at: schedule.colorIndex))
            } else if schedule.isEnabled {
                Text("已完成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
