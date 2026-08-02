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
                    if category == SoundCatalog.availableCategories.last {
                        Text("這些都是 iOS 內建的 Apple 官方音效，App 本身沒有夾帶任何鈴聲檔。點一下即可試聽。")
                    }
                }
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
                    if option.englishName != option.name {
                        Text(option.englishName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if soundID == option.id {
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
