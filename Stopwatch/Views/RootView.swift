//
//  RootView.swift
//  Stopwatch
//

import SwiftUI

struct RootView: View {
    @Environment(ReminderController.self) private var controller

    @State private var editingSchedule: AlarmSchedule?
    @State private var draftSchedule: AlarmSchedule?
    @State private var showingAppInfo = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                NotificationPermissionBanner()

                List {
                    Section {
                        clockCard
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    schedulesSection
                    historySection
                }
                .listStyle(.insetGrouped)
                // 刪掉最後一組排程時，「提醒排程」區段會從幾列排程整塊換成空白提示，
                // 高度一口氣多出兩百多點。沿用同一個 List 的話，空白提示會立刻以完整
                // 高度插進去，底下的「提醒紀錄」卻要等刪除動畫跑完才重新定位——實測
                // 有 0.4 秒兩塊疊在一起。換 id 讓 List 整個重建，版面同一幀到位。
                .id(controller.schedules.isEmpty)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("循環提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingAppInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("關於與功能說明")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        draftSchedule = AlarmSchedule.makeNew()
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
                    removeSchedules(leavingNone: controller.schedules.count == 1) {
                        controller.delete(schedule)
                    }
                }
                .equatable()
            }
            .sheet(item: $draftSchedule) { schedule in
                ScheduleEditorView(schedule: schedule, isNew: true) { created in
                    controller.addSchedule(created)
                }
                .equatable()
            }
            .sheet(isPresented: $showingAppInfo) {
                AppInfoView()
            }
            .overlay(alignment: .top) {
                flashBanner
            }
            .animation(.spring(duration: 0.35), value: controller.flash)
        }
    }

    // MARK: - 時鐘

    private var clockCard: some View {
        VStack(spacing: 10) {
            Text(TimeFormat.timeOfDayWithSeconds(controller.now))
                .font(.system(size: 56, weight: .light, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)

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
        if let next = controller.nextFire {
            HStack(spacing: 6) {
                Circle()
                    .fill(Palette.color(at: next.schedule.colorIndex))
                    .frame(width: 8, height: 8)
                Text("下一次 \(next.schedule.displayLabel) · \(TimeFormat.countdownOrTime(to: next.at, from: controller.now))")
                    .monospacedDigit()
            }
        } else if controller.schedules.isEmpty {
            Text("尚未設定提醒")
        } else {
            // 排程還在、只是都關了（響完會自己關掉，也可能是使用者關的），
            // 既不能說「尚未設定」，也不能一律說「都響完了」。
            Text("目前沒有進行中的提醒")
        }
    }

    // MARK: - 排程

    private var schedulesSection: some View {
        Section("提醒排程") {
            if controller.schedules.isEmpty {
                emptyState
            } else {
                ForEach(controller.schedules) { schedule in
                    ScheduleRow(schedule: schedule,
                                nextFire: controller.nextFireDate(for: schedule),
                                now: controller.now,
                                firedCount: controller.firedCount(for: schedule),
                                onTap: { editingSchedule = schedule },
                                onToggle: { controller.setEnabled($0, for: schedule) })
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            removeSchedules(leavingNone: controller.schedules.count == 1) {
                                controller.delete(schedule)
                            }
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
                .onDelete { offsets in
                    removeSchedules(leavingNone: offsets.count >= controller.schedules.count) {
                        controller.delete(atOffsets: offsets)
                    }
                }
            }
        }
    }

    /// 刪除排程。刪到一組都不剩的那一刀不做動畫。
    ///
    /// 與 List 上那個 `.id` 是一組的：`.id` 負責讓版面一次重建，這裡負責讓那次重建
    /// 不要再被套上轉場動畫，否則新舊兩份版面仍會交疊著淡入淡出。只在最後一刀關閉，
    /// 中間還有排程時照樣保留正常的刪除動畫。
    private func removeSchedules(leavingNone: Bool, perform: () -> Void) {
        guard leavingNone else {
            perform()
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, perform)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell.badge")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("還沒有任何提醒")
                .font(.headline)
            Text("例如設「14:00 開始，每 5 分鐘」，時鐘走到 14:00、14:05、14:10… 都會響一次。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("新增提醒") { draftSchedule = AlarmSchedule.makeNew() }
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
            Section {
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
                                .accessibilityLabel("背景期間的排定提醒")
                        }
                        Text(TimeFormat.timeOfDayWithSeconds(event.firedAt))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            } header: {
                HStack {
                    Text("提醒紀錄")
                    Spacer()
                    Button("清除") { controller.clearHistory() }
                        .font(.caption)
                        .textCase(nil)
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
                    Text(TimeFormat.timeOfDay(flash.at))
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
}

// MARK: - 排程列

private struct ScheduleRow: View {
    let schedule: AlarmSchedule
    let nextFire: Date?
    let now: Date
    let firedCount: Int
    let onTap: () -> Void
    let onToggle: (Bool) -> Void

    private var soundName: String {
        SoundCatalog.resolved(id: schedule.soundID)?.name ?? "預設"
    }

    /// 音效摘要，例如「鐘聲 × 3 · 已響 16 次」。
    ///
    /// 「已響 N 次」整串用不斷行字元黏起來。中文可以在任兩個字之間斷行，
    /// 放著不管的話寬度一不夠，就會看到「已」留在上一行、「響 16 次」掉到下一行。
    private var soundSummary: String {
        var text = soundName
        if schedule.chimeCount > 1 {
            text += " ×\u{00A0}\(schedule.chimeCount)"
        }
        if firedCount > 0 {
            text += " · 已\u{2060}響\u{00A0}\(firedCount)\u{00A0}次"
        }
        return text
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

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "speaker.wave.2.fill")
                        .accessibilityHidden(true)
                    Text(soundSummary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            // 倒數與外層開關都位於各自欄位的垂直中央，因此中心線會一致。
            if schedule.isEnabled, let nextFire {
                Text(TimeFormat.countdownOrTime(to: nextFire, from: now))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.color(at: schedule.colorIndex))
            }
        }
    }
}
