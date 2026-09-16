//
//  StopwatchApp.swift
//  Stopwatch
//

import SwiftUI
import UIKit
import UserNotifications
import OSLog

@main
struct StopwatchApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    @State private var controller = ReminderController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(controller)
                .task { controller.handleLaunch() }
        }
        .onChange(of: scenePhase) { _, phase in
            controller.handleScenePhase(phase)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// 已排入系統的通知一律由系統呈現及播放，包括前景送達。
    /// 不以 applicationState 分流：通知回呼與計時器可能分別位於鎖定切換的兩側，
    /// 若一邊隱藏通知、另一邊跳過 App 播放，就會漏響。
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // 實際送達回呼與預定時間分開記錄，不把 Timer 推算當作已成功響鈴。
        if let timestamp = notification.request.identifier.split(separator: "-").last.flatMap({ Double($0) }) {
            let delay = Date().timeIntervalSince1970 - timestamp
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "Stopwatch", category: "ReminderDelivery")
                .info("Foreground notification delivery delay: \(delay, privacy: .public) seconds")
        }
        completionHandler([.banner, .list, .sound])
    }
}
