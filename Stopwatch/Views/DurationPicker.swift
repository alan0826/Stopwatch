//
//  DurationPicker.swift
//  Stopwatch
//

import SwiftUI

/// 時 / 分 / 秒三欄滾輪，用來輸入碼表上的秒數。
struct DurationPicker: View {
    @Binding var seconds: TimeInterval
    var maxHours = 23

    private var hours: Binding<Int> {
        Binding(get: { Int(seconds) / 3600 },
                set: { update(hours: $0, minutes: nil, secs: nil) })
    }

    private var minutes: Binding<Int> {
        Binding(get: { (Int(seconds) % 3600) / 60 },
                set: { update(hours: nil, minutes: $0, secs: nil) })
    }

    private var secs: Binding<Int> {
        Binding(get: { Int(seconds) % 60 },
                set: { update(hours: nil, minutes: nil, secs: $0) })
    }

    private func update(hours newHours: Int?, minutes newMinutes: Int?, secs newSecs: Int?) {
        let total = Int(max(seconds, 0))
        let h = newHours ?? total / 3600
        let m = newMinutes ?? (total % 3600) / 60
        let s = newSecs ?? total % 60
        seconds = TimeInterval(h * 3600 + m * 60 + s)
    }

    var body: some View {
        HStack(spacing: 0) {
            wheel(range: 0...maxHours, unit: "時", selection: hours)
            wheel(range: 0...59, unit: "分", selection: minutes)
            wheel(range: 0...59, unit: "秒", selection: secs)
        }
        .frame(height: 150)
    }

    private func wheel(range: ClosedRange<Int>, unit: String, selection: Binding<Int>) -> some View {
        Picker("", selection: selection) {
            ForEach(range, id: \.self) { value in
                Text("\(value) \(unit)").tag(value)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .clipped()
    }
}
