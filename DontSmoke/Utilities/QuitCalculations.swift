import Foundation

enum QuitCalculations {
    struct Duration: Equatable {
        let days: Int
        let hours: Int
        let minutes: Int
        var totalHours: Int { days * 24 + hours }
    }
    static func costPerCigarette(packPrice: Decimal, packSize: Int) -> Decimal {
        guard packSize > 0 else { return 0 }; return packPrice / Decimal(packSize)
    }
    static func dailySpending(packPrice: Decimal, packSize: Int, cigarettesPerDay: Int) -> Decimal {
        costPerCigarette(packPrice: packPrice, packSize: packSize) * Decimal(max(0, cigarettesPerDay))
    }
    static func elapsedDays(since date: Date, now: Date = .now, calendar: Calendar = .current) -> Int {
        duration(since: date, now: now, calendar: calendar).days
    }
    static func duration(since date: Date, now: Date = .now, calendar: Calendar = .current) -> Duration {
        guard now > date else { return Duration(days: 0, hours: 0, minutes: 0) }
        let parts = calendar.dateComponents([.day, .hour, .minute], from: date, to: now)
        return Duration(days: max(0, parts.day ?? 0), hours: max(0, parts.hour ?? 0), minutes: max(0, parts.minute ?? 0))
    }
    static func elapsedDayFraction(since date: Date, now: Date = .now) -> Decimal {
        Decimal(max(0, now.timeIntervalSince(date))) / Decimal(86_400)
    }
    static func cigarettesAvoided(profile: QuitProfile, now: Date = .now) -> Int {
        cigarettesAvoided(since: profile.quitDate, now: now, cigarettesPerDay: profile.cigarettesPerDay)
    }
    static func cigarettesAvoided(since date: Date, now: Date, cigarettesPerDay: Int) -> Int {
        guard cigarettesPerDay > 0, now > date else { return 0 }
        let elapsedDays = now.timeIntervalSince(date) / 86_400
        return max(0, Int((elapsedDays * Double(cigarettesPerDay)).rounded(.down)))
    }
    static func moneySaved(profile: QuitProfile, now: Date = .now) -> Decimal {
        moneySaved(cigarettesAvoided: cigarettesAvoided(profile: profile, now: now), costPerCigarette: costPerCigarette(packPrice: profile.packPrice, packSize: profile.packSize))
    }
    static func moneySaved(cigarettesAvoided: Int, costPerCigarette: Decimal) -> Decimal {
        Decimal(max(0, cigarettesAvoided)) * max(0, costPerCigarette)
    }
    static func currency(_ value: Decimal, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .autoupdatingCurrent
        formatter.currencyCode = code
        formatter.maximumFractionDigits = value.isWhole ? 0 : 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(code) \(value)"
    }
}

enum CurrencySupport {
    private static let commonCodes = ["INR", "USD", "GBP", "EUR", "AUD", "CAD", "JPY", "SGD", "AED"]
    static var defaultCode: String { Locale.current.currency?.identifier ?? "USD" }
    static var availableCodes: [String] { Array(Set(commonCodes + [defaultCode])).sorted() }

    static func symbol(for code: String) -> String {
        let formatter = NumberFormatter(); formatter.numberStyle = .currency; formatter.locale = .autoupdatingCurrent; formatter.currencyCode = code
        return formatter.currencySymbol ?? code
    }
    static func name(for code: String) -> String { Locale.current.localizedString(forCurrencyCode: code) ?? code }
    static func pickerLabel(for code: String) -> String { "\(code) · \(symbol(for: code)) · \(name(for: code))" }
}

private extension Decimal {
    var isWhole: Bool {
        let number = NSDecimalNumber(decimal: self).doubleValue
        return number.rounded() == number
    }
}
