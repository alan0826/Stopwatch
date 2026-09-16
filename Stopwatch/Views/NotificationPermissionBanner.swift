//
//  NotificationPermissionBanner.swift
//  Stopwatch
//

import SwiftUI
import UIKit

/// 只在使用者已建立需要背景送達的提醒後顯示。
/// AlarmKit 與一般通知是兩種獨立授權，因此同時用到兩種提醒時可能顯示兩張說明。
struct NotificationPermissionBanner: View {
    @Environment(ReminderController.self) private var controller

    private var shouldShowAlarmBanner: Bool {
        guard controller.hasEnabledAlarmSchedules else { return false }
        return controller.alarmPermissionStatus == .notDetermined
            || controller.alarmPermissionStatus == .denied
    }

    private var shouldShowNotificationBanner: Bool {
        guard controller.hasEnabledNotificationSchedules else { return false }
        return controller.notificationStatus == .notDetermined
            || controller.notificationStatus == .denied
    }

    private var notificationSettingsMessage: String? {
        guard controller.hasEnabledNotificationSchedules,
              controller.notificationSettingsLoaded,
              controller.notificationStatus == .authorized
                || controller.notificationStatus == .provisional
                || controller.notificationStatus == .ephemeral
        else { return nil }

        if controller.notificationStatus == .provisional
            || controller.notificationStatus == .ephemeral {
            return "通知目前是暫時或靜默授權，可能只會進入通知中心。點一下前往設定，改為允許立即通知。"
        }

        // 這幾項各自獨立，任何一項被關掉都會讓提醒安靜落進通知中心。
        // 以前只回報排在最前面的那一項，使用者照著開完卻還是不會響，
        // 只會以為 App 壞了，所以一次把缺的全部列出來。
        var missing: [String] = []
        if !controller.notificationLockScreenEnabled { missing.append("鎖定畫面") }
        if !controller.notificationAlertsEnabled { missing.append("橫幅") }
        if !controller.notificationSoundsEnabled { missing.append("聲音") }
        if !controller.notificationTimeSensitiveEnabled { missing.append("時效性通知") }
        guard !missing.isEmpty else { return nil }

        let list = missing.map { "「\($0)」" }.joined(separator: "、")
        var effect = "提醒會安靜落進通知中心"
        if !controller.notificationLockScreenEnabled || !controller.notificationAlertsEnabled {
            effect += "，螢幕不會亮"
        }
        if !controller.notificationSoundsEnabled {
            effect += "，也不會響鈴"
        }
        if controller.notificationScheduledDeliveryEnabled,
           !controller.notificationTimeSensitiveEnabled {
            effect += "；「排定摘要」開著時，時效性通知一關，提醒會被留到摘要時段才送達"
        }
        return "iOS 設定裡的 \(list) 是關閉的，\(effect)。點一下前往設定開啟。"
    }

    private var schedulingError: String? {
        controller.alarmSchedulingError ?? controller.notificationSchedulingError
    }

    var body: some View {
        if shouldShowAlarmBanner || shouldShowNotificationBanner
            || notificationSettingsMessage != nil || schedulingError != nil {
            VStack(spacing: 8) {
                if let schedulingError {
                    errorLabel(schedulingError)
                }

                if controller.hasEnabledAlarmSchedules {
                    switch controller.alarmPermissionStatus {
                    case .notDetermined:
                        permissionButton(
                            icon: "alarm.fill",
                            title: "開啟系統鬧鐘",
                            message: "單次或每日鬧鐘可在需要時突破靜音與專注模式。",
                            hint: "顯示 iOS 鬧鐘權限提示"
                        ) {
                            controller.requestAlarmPermissionIfNeeded()
                        }
                    case .denied:
                        settingsButton(
                            icon: "alarm.waves.left.and.right.slash",
                            title: "系統鬧鐘已關閉",
                            message: "單次與每日鬧鐘無法在背景送達。點一下前往設定開啟。",
                            hint: "開啟「設定」以允許系統鬧鐘"
                        )
                    case .unavailable, .authorized:
                        EmptyView()
                    }
                }

                if controller.hasEnabledNotificationSchedules,
                   controller.notificationStatus == .notDetermined {
                    permissionButton(
                        icon: "bell.badge.fill",
                        title: "開啟背景提醒",
                        message: "允許通知後，有限連響與間隔提醒才能在背景或鎖定螢幕時送達。",
                        hint: "顯示 iOS 通知權限提示"
                    ) {
                        controller.requestNotificationPermissionIfNeeded()
                    }
                } else if controller.hasEnabledNotificationSchedules,
                          controller.notificationStatus == .denied {
                    settingsButton(
                        icon: "bell.slash.fill",
                        title: "通知已關閉",
                        message: "有限連響與間隔提醒無法在背景送達。點一下前往設定開啟。",
                        hint: "開啟「設定」以允許通知"
                    )
                } else if let notificationSettingsMessage {
                    settingsButton(
                        icon: "speaker.slash.fill",
                        title: "背景通知設定不完整",
                        message: notificationSettingsMessage,
                        hint: "開啟「設定」以允許通知提示與聲音"
                    )
                }
            }
            .bannerContainer()
        }
    }

    private func permissionButton(
        icon: String,
        title: String,
        message: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            bannerLabel(icon: icon, title: title, message: message)
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
    }

    private func settingsButton(icon: String,
                                title: String,
                                message: String,
                                hint: String) -> some View {
        Button {
            // 直接進入這個 App 的通知設定，避免使用者還得再找一次「通知」。
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            bannerLabel(icon: icon, title: title, message: message)
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
    }

    private func bannerLabel(icon: String, title: String, message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    private func errorLabel(_ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text("背景提醒排程失敗")
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.red.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.red.opacity(0.35), lineWidth: 1)
        )
    }
}

private extension View {
    func bannerContainer() -> some View {
        padding(.horizontal, 16)
            .padding(.top, 8)
    }
}
