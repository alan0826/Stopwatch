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
                Text("點一下即可試聽，試聽使用媒體音量。背景與鎖定螢幕時改由系統鬧鐘或通知送達，音量由 iOS 控制。")
            }
        }
        .navigationTitle("鈴聲")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            SoundPlayer.shared.stopAll()
        }
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
#Preview {
    NavigationStack {
        SoundPickerView(soundID: .constant(""))
    }
}
