import Foundation
import UserNotifications

enum CravingNotificationPermission: Equatable { case notDetermined, authorized, denied, provisional }

struct CravingReminderRequest: Equatable {
    static let leadTimeMinutes = 10
    let identifier: String
    let triggerID: UUID
    let cravingTime: DateComponents
    let notificationTime: DateComponents
    let title: String
    let body: String
}

struct CravingReminderPlan: Equatable {
    let id: UUID
    let trigger: CravingTrigger
    let cravingTime: Date?
    let enabled: Bool
}

protocol CravingNotificationCenter: Sendable {
    func permission() async -> CravingNotificationPermission
    func requestAuthorization() async throws -> Bool
    func add(_ request: CravingReminderRequest) async throws
    func remove(identifier: String) async
    func removeAllCravingRequests() async
}

protocol CravingReminderScheduling: Sendable {
    func permission() async -> CravingNotificationPermission
    func requestAuthorizationIfNeeded() async -> CravingNotificationPermission
    func scheduleReminder(id: UUID, trigger: CravingTrigger, cravingTime: Date) async
    func cancelReminder(id: UUID) async
    func cancelAllCravingReminders() async
    func synchronize(_ plans: [CravingReminderPlan]) async
}

struct CravingReminderScheduler: CravingReminderScheduling {
    let center: any CravingNotificationCenter
    var calendar = Calendar.autoupdatingCurrent

    func permission() async -> CravingNotificationPermission { await center.permission() }
    func requestAuthorizationIfNeeded() async -> CravingNotificationPermission {
        let current = await center.permission()
        guard current == .notDetermined else { return current }
        do { return try await center.requestAuthorization() ? .authorized : .denied }
        catch { return .denied }
    }
    func scheduleReminder(id: UUID, trigger: CravingTrigger, cravingTime: Date) async {
        let request = Self.makeRequest(id: id, trigger: trigger, cravingTime: cravingTime, calendar: calendar)
        await center.remove(identifier: request.identifier)
        try? await center.add(request)
    }
    func cancelReminder(id: UUID) async { await center.remove(identifier: Self.identifier(for: id)) }
    func cancelAllCravingReminders() async { await center.removeAllCravingRequests() }
    func synchronize(_ plans: [CravingReminderPlan]) async {
        for plan in plans {
            guard plan.enabled, let time = plan.cravingTime else { await cancelReminder(id: plan.id); continue }
            await scheduleReminder(id: plan.id, trigger: plan.trigger, cravingTime: time)
        }
    }

    static func identifier(for id: UUID) -> String { "craving.\(id.uuidString.lowercased())" }
    static func makeRequest(id: UUID, trigger: CravingTrigger, cravingTime: Date, calendar: Calendar) -> CravingReminderRequest {
        let intended = calendar.dateComponents([.hour, .minute], from: cravingTime)
        let reminderDate = calendar.date(byAdding: .minute, value: -CravingReminderRequest.leadTimeMinutes, to: cravingTime) ?? cravingTime
        let fire = calendar.dateComponents([.hour, .minute], from: reminderDate)
        let variants = ["Take a moment for yourself.", "Remember why you started.", "You’ve already kept a lot.", "Before the craving arrives, give yourself a minute."]
        let index = id.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) } % variants.count
        return CravingReminderRequest(identifier: identifier(for: id), triggerID: id, cravingTime: intended,
            notificationTime: fire, title: "A usual craving time is coming up", body: variants[index])
    }
}

final class SystemCravingNotificationCenter: @unchecked Sendable, CravingNotificationCenter {
    static let shared = SystemCravingNotificationCenter()
    private let center = UNUserNotificationCenter.current()
    private init() {}
    func permission() async -> CravingNotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .ephemeral: .authorized
        case .denied: .denied
        case .provisional: .provisional
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }
    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func add(_ request: CravingReminderRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title; content.body = request.body; content.sound = .default
        content.userInfo = ["destination": "cravingRescue"]
        let trigger = UNCalendarNotificationTrigger(dateMatching: request.notificationTime, repeats: true)
        try await center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
    }
    func remove(identifier: String) async { center.removePendingNotificationRequests(withIdentifiers: [identifier]) }
    func removeAllCravingRequests() async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("craving.") })
    }
}

enum NotificationService {
    static let scheduler: any CravingReminderScheduling = CravingReminderScheduler(center: SystemCravingNotificationCenter.shared)
}
