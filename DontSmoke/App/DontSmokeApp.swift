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

    var body: some View {
        Group {
            if let profile = profiles.first(where: \.onboardingCompleted) {
                MainTabView(profile: profile)
            } else {
                OnboardingFlowView()
            }
        }
        .preferredColorScheme(.dark)
    }
}
