//
//  ReminderWidgetBundle.swift
//  ReminderWidget
//

import SwiftUI
import WidgetKit

/// AlarmKit 的警示畫面（鎖定畫面、動態島、待機顯示）是由 ActivityKit 向
/// App 的 Widget Extension 要內容的。少了這個 extension，系統鬧鐘到點時
/// 只會出現一個空白的載入畫面，幾秒後就被系統收掉 —— 等於完全不會響。
@main
struct ReminderWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 26.0, *) {
            ReminderAlarmWidget()
        }
    }
}
