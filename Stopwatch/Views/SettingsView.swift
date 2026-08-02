//
//  SettingsView.swift
//  Stopwatch
//

import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(StopwatchController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var controller = controller

        NavigationStack {
            Form {
                Section {
                    Toggle("碼表執行時不自動鎖定螢幕", isOn: $controller.keepScreenOn)
                } footer: {
                    Text("""
                    切到背景或鎖定螢幕時，響鈴改由系統通知發出。

                    iOS 限制每個 App 最多只能預先排 64 則通知，本 App 使用 58 則。單獨一組「每 5 分鐘」約可撐 4.8 小時；同時開多組排程時會共用這個額度，用完之後就不會再響，直到你回到 App（回來時會自動重新排下一批）。長時間放著不管的話，記得偶爾打開 App 一次。
                    """)
                }

                Section {
                    HStack {
                        Text("通知權限")
                        Spacer()
                        Text(statusText)
                            .foregroundStyle(statusColor)
                    }
                    if controller.notificationStatus != .authorized {
                        Button("前往系統設定") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                } footer: {
                    Text("App 在背景時要靠通知權限才會出聲。")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { controller.refreshNotificationStatus() }
        }
    }

    private var statusText: String {
        switch controller.notificationStatus {
        case .authorized, .provisional, .ephemeral: return "已允許"
        case .denied: return "已拒絕"
        case .notDetermined: return "尚未詢問"
        @unknown default: return "未知"
        }
    }

    private var statusColor: Color {
        switch controller.notificationStatus {
        case .authorized, .provisional, .ephemeral: return .green
        case .denied: return .red
        default: return .secondary
        }
    }
}
