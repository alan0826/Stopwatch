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

    @State private var controller = StopwatchController()
    @State private var alarmStore = AlarmStore()
    @State private var lapStopwatch = LapStopwatch()
    @State private var countdownTimer = CountdownTimer()

    var body: some Scene {
        WindowGroup {
            ClockTabView()
                .environment(controller)
                .environment(alarmStore)
                .environment(lapStopwatch)
                .environment(countdownTimer)
                .task {
                    controller.refreshNotificationStatus()
                    controller.requestNotificationPermissionIfNeeded()
                    alarmStore.reschedule()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            controller.handleScenePhase(phase)
            if phase == .active {
                lapStopwatch.refresh()
                countdownTimer.refresh()
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([Self.alarmCategory()])
        return true
    }

    /// 間隔提醒與計時器在前景時由 App 自己播放鈴聲，不再重複顯示通知；
    /// 鬧鐘則照常顯示橫幅並出聲。
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let identifier = notification.request.identifier
        if identifier.hasPrefix(NotificationID.reminder) || identifier.hasPrefix(NotificationID.timer) {
            completionHandler([])
        } else {
            completionHandler([.banner, .sound, .list])
        }
    }

    /// 處理鬧鐘的「稍後提醒」。
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == NotificationID.snoozeAction,
           let content = response.notification.request.content.mutableCopy() as? UNMutableNotificationContent {
            let request = UNNotificationRequest(
                identifier: "\(NotificationID.alarm)snooze-\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: NotificationID.snoozeInterval,
                                                           repeats: false)
            )
            center.add(request)
        }
        completionHandler()
    }

    private static func alarmCategory() -> UNNotificationCategory {
        let snooze = UNNotificationAction(identifier: NotificationID.snoozeAction,
                                          title: "稍後提醒",
                                          options: [])
        let stop = UNNotificationAction(identifier: NotificationID.stopAction,
                                        title: "停止",
                                        options: [.destructive])
        return UNNotificationCategory(identifier: NotificationID.alarmCategory,
                                      actions: [snooze, stop],
                                      intentIdentifiers: [],
                                      options: [])
    }
}
