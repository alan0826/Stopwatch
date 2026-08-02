//
//  ClockTabView.swift
//  Stopwatch
//

import SwiftUI

/// 分頁配置。「循環提醒」是這個 App 的主功能，也是內建「時鐘」做不到的事，
/// 所以放在第一頁；鬧鐘／碼錶／計時器是附帶的常用工具。
struct ClockTabView: View {
    var body: some View {
        TabView {
            Tab("循環提醒", systemImage: "bell.badge.fill") {
                RootView()
            }
            Tab("鬧鐘", systemImage: "alarm.fill") {
                AlarmsView()
            }
            Tab("碼錶", systemImage: "stopwatch.fill") {
                LapStopwatchView()
            }
            Tab("計時器", systemImage: "timer") {
                CountdownTimerView()
            }
        }
    }
}
