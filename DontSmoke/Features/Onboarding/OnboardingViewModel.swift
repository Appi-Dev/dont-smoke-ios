import Foundation
import SwiftUI

@MainActor @Observable
final class OnboardingViewModel {
    var step = 0
    var quitDate = Date()
    var dateChoice = 0
    var cigarettesPerDay = 10
    var packPriceText = "200"
    var packSize = 20
    var currencyCode = CurrencySupport.defaultCode
    var reasons: Set<QuitReason> = []
    var primaryReason: QuitReason?
    var personalReasonText = ""
    var triggers: Set<CravingTrigger> = []
    var triggerTimes: [CravingTrigger: Date] = [:]
    var notificationPreference: NotificationPreference = .notAsked
    var wantsGoal = false
    var goalName = ""
    var goalAmountText = ""
    var goalIcon = "💰"

    var packPrice: Decimal { Decimal(string: packPriceText) ?? 0 }
    var dailySpend: Decimal { QuitCalculations.dailySpending(packPrice: packPrice, packSize: packSize, cigarettesPerDay: cigarettesPerDay) }
    var timedTriggers: [CravingTrigger] { triggers.filter(\.predictable).sorted { $0.rawValue < $1.rawValue } }
    var canContinue: Bool {
        switch step { case 1: cigarettesPerDay > 0; case 2: packPrice > 0 && packSize > 0; case 3: !reasons.isEmpty && primaryReason != nil
        case 8: !wantsGoal || (!goalName.trimmingCharacters(in: .whitespaces).isEmpty && (Decimal(string: goalAmountText) ?? 0) > 0); default: true }
    }

    func next() { withAnimation(.easeInOut(duration: 0.25)) { step = min(3, step + 1) } }
    func back() { withAnimation(.easeInOut(duration: 0.25)) { step = max(0, step - 1) } }
    func chooseDate(_ choice: Int) {
        dateChoice = choice
        if choice == 0 { quitDate = .now }
        if choice == 1 { quitDate = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now }
    }
    func toggleReason(_ reason: QuitReason) {
        if reasons.remove(reason) == nil { reasons.insert(reason) }
        if !reasons.contains(primaryReason ?? .other) { primaryReason = reasons.first }
    }
    func toggleTrigger(_ trigger: CravingTrigger) {
        if triggers.remove(trigger) == nil { triggers.insert(trigger); if trigger.predictable { triggerTimes[trigger] = defaultTime(for: trigger) } }
        else { triggerTimes[trigger] = nil }
    }
    private func defaultTime(for trigger: CravingTrigger) -> Date {
        let hour: Int = switch trigger { case .morningCoffee: 8; case .afterBreakfast: 9; case .afterLunch: 14; case .afterDinner: 21; case .lateNight: 23; default: 12 }
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
    }
}
