import Foundation

enum ProductWalkthroughPage: Int, CaseIterable, Identifiable {
    case progress, gains, myWhy, craving, keepWhatYouGained
    var id: Int { rawValue }
    var headline: String {
        switch self {
        case .progress: "Every smoke-free minute counts."
        case .gains: "See what you’re gaining."
        case .myWhy: "Come back to your reason."
        case .craving: "When a craving hits, you don’t have to face it alone."
        case .keepWhatYouGained: "Keep what you’ve gained."
        }
    }
    var subtitle: String {
        switch self {
        case .progress: "This is how long you’ve kept going."
        case .gains: "Every cigarette you skip means more money kept and fewer cigarettes smoked."
        case .myWhy: "When motivation gets difficult, remember why you started."
        case .craving: "Tap ‘I WANT TO SMOKE’ and take a few minutes. We can also remind you before usual craving times."
        case .keepWhatYouGained: "Don’t focus on what you gave up. Focus on what you’ve kept."
        }
    }
}

struct ProductWalkthroughState {
    var page: ProductWalkthroughPage = .progress
    let isReplay: Bool
    var isLastPage: Bool { page == .keepWhatYouGained }
    mutating func next() { page = ProductWalkthroughPage(rawValue: page.rawValue + 1) ?? page }
    mutating func back() { page = ProductWalkthroughPage(rawValue: page.rawValue - 1) ?? page }
    func finish(_ reason: ProductWalkthroughCompletionReason, defaults: UserDefaults = .standard) {
        guard !isReplay else { return }
        defaults.set(true, forKey: ProductWalkthroughPreferences.seenKey)
    }
}

enum ProductWalkthroughCompletionReason { case skipped, started }

enum ProductWalkthroughPreferences {
    static let seenKey = "hasSeenProductWalkthrough"
    static func shouldPresent(onboardingCompleted: Bool, hasSeen: Bool) -> Bool {
        onboardingCompleted && !hasSeen
    }
}
