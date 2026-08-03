//
//  StopwatchApp.swift
//  Stopwatch
//

import SwiftUI
import UserNotifications

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

    /// 前景時提醒由 App 自己播鈴聲並在畫面上閃提示，不需要再顯示一次通知。
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }
}
