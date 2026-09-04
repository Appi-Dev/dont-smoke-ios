import SwiftUI
import SwiftData

@main
struct DontSmokeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup { RootView() }
            .modelContainer(for: [QuitProfile.self, SavingsGoal.self, CravingSchedule.self])
    }
}

struct RootView: View {
    @Query private var profiles: [QuitProfile]
    @AppStorage(ProductWalkthroughPreferences.seenKey) private var hasSeenProductWalkthrough = false
    @AppStorage(FirstRunPreferences.welcomeSeenKey) private var hasSeenWelcome = false

    var body: some View {
        Group {
            if let profile = profiles.first(where: \.onboardingCompleted) {
                if ProductWalkthroughPreferences.shouldPresent(onboardingCompleted: profile.onboardingCompleted, hasSeen: hasSeenProductWalkthrough) {
                    ProductWalkthroughView(profile: profile) { hasSeenProductWalkthrough = true }
                } else {
                    MainTabView(profile: profile)
                }
            } else {
                if FirstRunPreferences.shouldShowWelcome(hasProfile: false, hasSeenWelcome: hasSeenWelcome) {
                    WelcomeView { hasSeenWelcome = true }
                } else {
                    OnboardingFlowView()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
