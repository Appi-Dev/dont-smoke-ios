import Foundation
import SwiftData

enum QuitReason: String, CaseIterable, Identifiable, Codable {
    case family, children, partner, health, money, fitness, control, other
    var id: String { rawValue }
    var title: String { switch self {
    case .family: "❤️ My family"; case .children: "👶 My children"; case .partner: "💑 My partner"
    case .health: "🫀 My health"; case .money: "💰 My money"; case .fitness: "🏃 My fitness"
    case .control: "🧠 Taking back control"; case .other: "✨ Something else" } }
    var payoff: String { title.dropFirst(2).trimmingCharacters(in: .whitespaces) }
    var isPersonal: Bool { [.family, .children, .partner].contains(self) }
}

enum CravingTrigger: String, CaseIterable, Identifiable, Codable {
    case morningCoffee, afterBreakfast, afterLunch, afterDinner, driving, workStress, alcohol, social, boredom, lateNight, other
    var id: String { rawValue }
    var title: String { switch self {
    case .morningCoffee: "☕ Morning tea / coffee"; case .afterBreakfast: "🍳 After breakfast"; case .afterLunch: "🍛 After lunch"
    case .afterDinner: "🍽 After dinner"; case .driving: "🚗 While driving"; case .workStress: "😤 Work stress"
    case .alcohol: "🍺 While drinking"; case .social: "👥 With friends"; case .boredom: "😴 When bored"
    case .lateNight: "🌙 Late at night"; case .other: "Other" } }
    var predictable: Bool { [.morningCoffee, .afterBreakfast, .afterLunch, .afterDinner, .lateNight].contains(self) }
    var timingQuestion: String { "Around what time is \(title.dropFirst(2).lowercased()) usually?" }
}

enum NotificationPreference: String, Codable { case notAsked, enabled, declined, deferred }

@Model final class QuitProfile {
    @Attribute(.unique) var id: UUID
    var quitDate: Date
    var cigarettesPerDay: Int
    var packPrice: Decimal
    var packSize: Int
    var currencyCode: String = "INR"
    var primaryReasonRaw: String
    var reasonRaws: [String]
    var personalReasonText: String?
    var triggerRaws: [String]
    var notificationPreferenceRaw: String
    var onboardingCompleted: Bool
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \SavingsGoal.profile) var goals: [SavingsGoal]
    @Relationship(deleteRule: .cascade, inverse: \CravingSchedule.profile) var cravingSchedules: [CravingSchedule]

    init(quitDate: Date, cigarettesPerDay: Int, packPrice: Decimal, packSize: Int, currencyCode: String, primaryReason: QuitReason,
         reasons: [QuitReason], personalReasonText: String?, triggers: [CravingTrigger], notificationPreference: NotificationPreference) {
        id = UUID(); self.quitDate = quitDate; self.cigarettesPerDay = cigarettesPerDay; self.packPrice = packPrice
        self.packSize = packSize; self.currencyCode = currencyCode; primaryReasonRaw = primaryReason.rawValue; reasonRaws = reasons.map(\.rawValue)
        self.personalReasonText = personalReasonText; triggerRaws = triggers.map(\.rawValue)
        notificationPreferenceRaw = notificationPreference.rawValue; onboardingCompleted = true; createdAt = .now; goals = []; cravingSchedules = []
    }
    var primaryReason: QuitReason { QuitReason(rawValue: primaryReasonRaw) ?? .other }
}

@Model final class SavingsGoal {
    @Attribute(.unique) var id: UUID
    var name: String; var targetAmount: Decimal; var icon: String?; var createdAt: Date
    var profile: QuitProfile?
    init(name: String, targetAmount: Decimal, icon: String?) { id = UUID(); self.name = name; self.targetAmount = targetAmount; self.icon = icon; createdAt = .now }
}

@Model final class CravingSchedule {
    @Attribute(.unique) var id: UUID
    var triggerRaw: String; var preferredTime: Date; var profile: QuitProfile?
    init(trigger: CravingTrigger, preferredTime: Date) { id = UUID(); triggerRaw = trigger.rawValue; self.preferredTime = preferredTime }
}
