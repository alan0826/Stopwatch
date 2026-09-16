//
//  ReminderAlarmWidget.swift
//  ReminderWidget
//

import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

/// 系統鬧鐘（「持續響鈴直到停止」）響起時的呈現。
@available(iOS 26.0, *)
struct ReminderAlarmWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<ReminderMetadata>.self) { context in
            lockScreen(context.attributes, state: context.state)
                .padding(16)
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                        .font(.title2)
                        .foregroundStyle(context.attributes.tintColor)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(of: context.attributes))
                            .font(.headline)
                            .lineLimit(1)
                        Text(subtitle(for: context.state))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    stopButton(for: context.state, tint: context.attributes.tintColor)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                Text(subtitle(for: context.state))
                    .monospacedDigit()
                    .foregroundStyle(context.attributes.tintColor)
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(context.attributes.tintColor)
            }
        }
    }

    // MARK: - 鎖定畫面／橫幅

    @ViewBuilder
    private func lockScreen(_ attributes: AlarmAttributes<ReminderMetadata>,
                            state: AlarmPresentationState) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "alarm.fill")
                .font(.title)
                .foregroundStyle(attributes.tintColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(title(of: attributes))
                    .font(.headline)
                    .lineLimit(2)
                Text(subtitle(for: state))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            stopButton(for: state, tint: attributes.tintColor)
        }
    }

    /// Live Activity 上的按鈕只能由 App Intent 執行，按下就停掉這顆鬧鐘。
    @ViewBuilder
    private func stopButton(for state: AlarmPresentationState, tint: Color) -> some View {
        Button(intent: StopAlarmIntent(alarmID: state.alarmID.uuidString)) {
            Text("停止")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }

    // MARK: - 文字

    private func title(of attributes: AlarmAttributes<ReminderMetadata>) -> LocalizedStringResource {
        attributes.presentation.alert.title
    }

    private func subtitle(for state: AlarmPresentationState) -> String {
        switch state.mode {
        case .alert(let alert):
            // 不能自己拼 "%02d:%02d"：12 小時制的地區會看到 22:07 而不是 10:07 PM。
            let components = DateComponents(year: 2001, month: 1, day: 1,
                                            hour: alert.time.hour, minute: alert.time.minute)
            guard let date = Calendar.current.date(from: components) else { return "" }
            return Self.timeFormatter.string(from: date)
        case .countdown(let countdown):
            return Self.timeFormatter.string(from: countdown.fireDate)
        case .paused:
            return "已暫停"
        @unknown default:
            return ""
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("j:mm")
        return formatter
    }()
}
