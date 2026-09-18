//
//  AppInfoView.swift
//  Stopwatch
//

import SwiftUI

/// 列出 App 的完整功能與系統需求。
struct AppInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("完整功能") {
                    feature("repeat.circle", "間隔與單次提醒",
                            "可設定第一次響鈴時刻、重複間隔、結束時間、每日重複、鈴聲、連響次數與顏色。")
                    feature("bell.badge", "背景提醒",
                            "有限連響與間隔提醒使用本地通知。儲存提醒後，主畫面會顯示權限說明，由你點擊後才要求通知權限。")
                    feature("alarm.waves.left.and.right", "持續響鈴直到停止",
                            systemAlarmDescription)
                    feature("rectangle.on.rectangle", "鎖定畫面控制",
                            "啟用系統鬧鐘時，iOS 會在鎖定畫面顯示鬧鐘；支援的 iPhone 也會顯示動態島介面與停止按鈕。")
                    feature("clock.arrow.circlepath", "提醒紀錄",
                            "主畫面會保留本機提醒紀錄，方便確認排定時刻與使用情形。")
                }

                Section {
                    LabeledContent("系統鬧鐘需求", value: "iOS 26 或更新版本")
                    LabeledContent("帳號／登入", value: "不需要")
                    LabeledContent("網路與第三方服務", value: "未使用")
                    LabeledContent("資料儲存", value: "只在此裝置")
                } header: {
                    Text("系統與隱私")
                } footer: {
                    Text("iOS 18～25 仍可使用所有一般通知提醒；「持續響鈴直到停止」需要 iOS 26 或更新版本。")
                }

                Section("版本") {
                    LabeledContent("App", value: "循環提醒")
                    LabeledContent("版本", value: versionText)
                }
            }
            .navigationTitle("關於循環提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var systemAlarmDescription: String {
        if #available(iOS 26.0, *) {
            return "單次提醒（可搭配每天重複）可選用 Apple AlarmKit，突破靜音與專注模式並持續響鈴，直到手動停止。授權只會在主畫面的可見說明卡中由你主動開啟。"
        }
        return "這項 Apple AlarmKit 功能需要 iOS 26 或更新版本；目前裝置會改用一般本地通知。"
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
