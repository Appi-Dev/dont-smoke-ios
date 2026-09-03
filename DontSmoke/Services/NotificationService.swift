import UserNotifications

@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private init() {}
    func requestAuthorization() async -> NotificationPreference {
        do { return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) ? .enabled : .declined }
        catch { return .declined }
    }
}
