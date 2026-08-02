//
//  SoundPickerView.swift
//  Stopwatch
//

import SwiftUI

struct SoundPickerView: View {
    @Binding var soundID: String

    var body: some View {
        List {
            Section {
                ForEach(SoundCatalog.options) { option in
                    row(for: option)
                }
            } footer: {
                Text("點一下即可試聽。App 在背景或鎖定螢幕時，提醒改由系統通知送出，音量吃的是「設定 → 聲音與觸覺回饋」裡的鈴聲音量，不是媒體音量。")
            }
        }
        .navigationTitle("鈴聲")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for option: SoundOption) -> some View {
        Button {
            soundID = option.id
            SoundPlayer.shared.preview(option)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name)
                        .foregroundStyle(Color.primary)
                    Text(option.englishName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // 舊版存下來的鈴聲代號可能已不存在，用解析後的結果比對才不會整份都沒打勾。
                if SoundCatalog.resolved(id: soundID)?.id == option.id {
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
