import SwiftUI
@preconcurrency import UserNotifications

@MainActor @Observable
final class AppNavigation {
    static let shared = AppNavigation()
    var shouldOpenCravingRescue = false
    private init() {}
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let opensRescue = response.notification.request.content.userInfo["destination"] as? String == "cravingRescue"
        completionHandler()
        Task { @MainActor in
            if opensRescue { AppNavigation.shared.shouldOpenCravingRescue = true }
        }
    }
}
