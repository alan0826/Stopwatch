//
//  LapStopwatchView.swift
//  Stopwatch
//

import SwiftUI

struct LapStopwatchView: View {
    @Environment(LapStopwatch.self) private var model

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(TimeFormat.stopwatch(model.elapsed))
                    .font(.system(size: 74, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(.horizontal)
                    .padding(.top, 24)
                    .frame(maxWidth: .infinity)

                controls
                    .padding(.vertical, 28)

                lapList
            }
            .navigationTitle("碼錶")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var controls: some View {
        HStack {
            circleButton(title: model.isRunning ? "圈數" : "重置", tint: .gray) {
                model.lapOrReset()
            }
            .disabled(!model.hasStarted)

            Spacer()

            circleButton(title: model.isRunning ? "停止" : "開始",
                         tint: model.isRunning ? .red : .green) {
                model.toggle()
            }
        }
        .padding(.horizontal, 40)
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

    private var lapList: some View {
        List {
            if model.hasStarted {
                lapRow(title: "圈數 \(model.currentLapIndex)",
                       value: model.currentLapDuration,
                       tint: .primary)
            }
            ForEach(model.laps) { lap in
                lapRow(title: "圈數 \(lap.index)",
                       value: lap.duration,
                       tint: tint(for: lap))
            }
        }
        .listStyle(.plain)
    }

    private func lapRow(title: String, value: TimeInterval, tint: Color) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(TimeFormat.stopwatch(value))
                .monospacedDigit()
        }
        .font(.body)
        .foregroundStyle(tint)
    }

    private func tint(for lap: LapStopwatch.Lap) -> Color {
        if lap.id == model.fastestLapID { return .green }
        if lap.id == model.slowestLapID { return .red }
        return .primary
    }
}
