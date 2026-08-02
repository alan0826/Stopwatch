//
//  CountdownTimerView.swift
//  Stopwatch
//

import SwiftUI

struct CountdownTimerView: View {
    @Environment(CountdownTimer.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            List {
                Section {
                    Group {
                        if model.isActive {
                            countdownRing
                        } else {
                            DurationPicker(seconds: $model.duration)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    controls
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section {
                    HStack {
                        Text("標籤")
                        Spacer()
                        TextField("計時器", text: $model.label)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        SoundPickerView(soundID: $model.soundID)
                    } label: {
                        LabeledContent("計時結束時",
                                       value: SoundCatalog.resolved(id: model.soundID)?.name ?? "預設")
                    }
                }

                if !model.recents.isEmpty {
                    Section("最近使用") {
                        ForEach(model.recents, id: \.self) { seconds in
                            HStack {
                                Text(TimeFormat.duration(seconds))
                                Spacer()
                                Button {
                                    model.startRecent(seconds)
                                } label: {
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.green)
                                }
                                .buttonStyle(.plain)
                                .disabled(model.isActive)
                                .accessibilityLabel("開始 \(TimeFormat.duration(seconds)) 的計時")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("計時器")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - 倒數環

    private var countdownRing: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemFill), lineWidth: 8)

            Circle()
                .trim(from: 0, to: model.progress)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 6) {
                Text(TimeFormat.countdown(model.remaining))
                    .font(.system(size: 58, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)

                HStack(spacing: 4) {
                    Image(systemName: "bell.fill")
                        .accessibilityHidden(true)
                    Text(model.endTimeText)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel("結束時間 \(model.endTimeText)")
            }
            .padding(36)
        }
        .frame(width: 240, height: 240)
        .padding(.vertical, 12)
    }

    // MARK: - 按鈕

    private var controls: some View {
        HStack {
            circleButton(title: "取消", tint: .gray) {
                model.cancel()
            }
            .disabled(!model.isActive)

            Spacer()

            circleButton(title: rightButtonTitle, tint: model.isRunning ? .orange : .green) {
                if model.isRunning {
                    model.pause()
                } else if model.isActive {
                    model.resume()
                } else {
                    model.start()
                }
            }
            .disabled(!model.isActive && !model.canStart)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
    }

    private var rightButtonTitle: String {
        if model.isRunning { return "暫停" }
        return model.isActive ? "繼續" : "開始"
    }

    private func circleButton(title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.title3)
                .frame(width: 82, height: 82)
                .background(Circle().fill(tint.opacity(0.18)))
                .overlay(Circle().stroke(tint.opacity(0.35), lineWidth: 1.5))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}
