import SwiftUI
import SwiftData

@main
struct DontSmokeApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
            .modelContainer(for: [QuitProfile.self, SavingsGoal.self, CravingSchedule.self])
    }
}

struct RootView: View {
    @Query private var profiles: [QuitProfile]
    @AppStorage(ProductWalkthroughPreferences.seenKey) private var hasSeenProductWalkthrough = false

    var body: some View {
        Group {
            if let profile = profiles.first(where: \.onboardingCompleted) {
                if ProductWalkthroughPreferences.shouldPresent(onboardingCompleted: profile.onboardingCompleted, hasSeen: hasSeenProductWalkthrough) {
                    ProductWalkthroughView(profile: profile) { hasSeenProductWalkthrough = true }
                } else {
                    MainTabView(profile: profile)
                }
            } else {
                OnboardingFlowView()
            }
        }
        .preferredColorScheme(.dark)
    }
}
