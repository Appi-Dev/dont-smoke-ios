import SwiftUI

enum FirstRunPreferences {
    static let welcomeSeenKey = "hasSeenWelcome"
    static func shouldShowWelcome(hasProfile: Bool, hasSeenWelcome: Bool) -> Bool { !hasProfile && !hasSeenWelcome }
}

struct WelcomeView: View {
    let getStarted: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: 44)
                Image(systemName: "leaf").font(.system(size: 46, weight: .light)).foregroundStyle(AppColor.sage)
                Text("Ready to quit for good?")
                    .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 18) {
                    benefit("clock", "Track your smoke-free progress")
                    benefit("banknote", "See the money you’re keeping")
                    benefit("photo", "Remember why you started")
                    benefit("wind", "Get support when a craving hits")
                }.padding(20).background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20))
                Text("Keep what you’ve gained.").font(.title2.bold()).foregroundStyle(AppColor.sage)
                PrimaryButton(title: "Get Started", action: getStarted)
                Spacer(minLength: 24)
            }.padding(.horizontal, 24)
        }.background(AppColor.background.ignoresSafeArea()).foregroundStyle(AppColor.text).preferredColorScheme(.dark)
    }
    private func benefit(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}
