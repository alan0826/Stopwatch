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
                    Text("切到背景時改用系統通知響鈴，最多預先排 58 次提醒，回到 App 會自動補排。")
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
