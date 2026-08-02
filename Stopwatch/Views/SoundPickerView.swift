//
//  SoundPickerView.swift
//  Stopwatch
//

import SwiftUI

struct SoundPickerView: View {
    @Binding var soundID: String

    var body: some View {
        List {
            ForEach(SoundCatalog.availableCategories) { category in
                Section {
                    ForEach(SoundCatalog.options(in: category)) { option in
                        row(for: option)
                    }
                } header: {
                    Text(category.rawValue)
                } footer: {
                    Text(footer(for: category))
                }
            }
        }
        .navigationTitle("鈴聲")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func footer(for category: SoundCategory) -> String {
        switch category {
        case .builtin:
            return "隨 App 附帶的音效，可以連響、鎖定螢幕時的通知也會用同一顆。點一下即可試聽。"
        case .system:
            return "由系統播放的內建提示音。App 在背景時，通知會改用系統預設提示音。"
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
                    if option.englishName != option.name {
                        Text(option.englishName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
