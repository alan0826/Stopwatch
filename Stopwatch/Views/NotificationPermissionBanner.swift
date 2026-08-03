//
//  NotificationPermissionBanner.swift
//  Stopwatch
//

import SwiftUI
import UIKit

/// 通知權限被拒時的提示。背景響鈴完全靠通知，關掉了就會安靜地失效，
/// 所以這件事必須在主畫面上講明白，而不是只放在設定頁裡。
struct NotificationPermissionBanner: View {
    @Environment(ReminderController.self) private var controller

    var body: some View {
        if controller.notificationStatus == .denied {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bell.slash.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("通知已關閉")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                        Text("App 切到背景或鎖定螢幕時不會響鈴。點一下前往設定開啟。")
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
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .accessibilityHint("開啟「設定」以允許通知")
        }
    }
}
