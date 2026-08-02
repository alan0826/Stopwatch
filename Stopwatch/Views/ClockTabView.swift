//
//  ClockTabView.swift
//  Stopwatch
//

import SwiftUI

/// 仿內建「時鐘」App 的分頁配置，最後多一頁是原本的碼表提醒。
struct ClockTabView: View {
    var body: some View {
        TabView {
            Tab("鬧鐘", systemImage: "alarm.fill") {
                AlarmsView()
            }
            Tab("碼錶", systemImage: "stopwatch.fill") {
                LapStopwatchView()
            }
            Tab("計時器", systemImage: "timer") {
                CountdownTimerView()
            }
            Tab("提醒", systemImage: "bell.badge.fill") {
                RootView()
            }
        }
    }
}
