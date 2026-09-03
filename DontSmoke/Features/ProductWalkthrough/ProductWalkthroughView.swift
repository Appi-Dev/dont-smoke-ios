import SwiftUI

struct ProductWalkthroughView: View {
    let profile: QuitProfile
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tour: ProductWalkthroughState
    @State private var referenceDate = Date.now

    init(profile: QuitProfile, isReplay: Bool = false, onFinish: @escaping () -> Void) {
        self.profile = profile
        self.onFinish = onFinish
        _tour = State(initialValue: ProductWalkthroughState(isReplay: isReplay))
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Don’t Smoke").font(.headline).foregroundStyle(AppColor.secondaryText)
                Spacer()
                Button("Skip") { finish(.skipped) }.frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Skip app tour")
            }.padding(.horizontal, 24)
            TabView(selection: $tour.page) {
                ForEach(ProductWalkthroughPage.allCases) { page in
                    WalkthroughStoryPage(page: page, profile: profile, now: referenceDate, isActive: tour.page == page)
                        .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            footer
        }
        .padding(.top, 8)
        .background(AppColor.background.ignoresSafeArea())
        .foregroundStyle(AppColor.text)
        .preferredColorScheme(.dark)
    }

    private var footer: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ForEach(ProductWalkthroughPage.allCases) { page in
                    Capsule().fill(page == tour.page ? AppColor.sage : AppColor.secondaryText.opacity(0.3))
                        .frame(width: page == tour.page ? 20 : 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(tour.page.rawValue + 1) of 5")
            .accessibilityValue(tour.page.headline)
            HStack(spacing: 16) {
                if tour.page != .progress {
                    Button("Back") { navigate { tour.back() } }
                        .frame(minWidth: 60, minHeight: 44)
                        .accessibilityLabel("Previous tour page")
                }
                PrimaryButton(title: tour.isLastPage ? "Start" : "Next") {
                    if tour.isLastPage { finish(.started) } else { navigate { tour.next() } }
                }
                .accessibilityHint(tour.isLastPage ? "Closes the app tour." : "Shows the next tour page.")
            }
        }.padding(.horizontal, 24).padding(.bottom, 16)
    }

    private func navigate(_ action: () -> Void) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25), action)
    }

    private func finish(_ reason: ProductWalkthroughCompletionReason) {
        tour.finish(reason)
        onFinish()
    }
}

private struct WalkthroughStoryPage: View {
    let page: ProductWalkthroughPage
    let profile: QuitProfile
    let now: Date
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                visual
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
                    .opacity(appeared ? 1 : 0)
                VStack(spacing: 14) {
                    Text(page.headline).font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(page.subtitle).font(.body).foregroundStyle(AppColor.secondaryText)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .accessibilityHidden(!isActive)
        .task(id: isActive) {
            guard isActive else { appeared = false; return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) { appeared = true }
        }
    }

    @ViewBuilder private var visual: some View {
        switch page {
        case .progress:
            timerPreview
        case .gains:
            gainsPreview
        case .myWhy:
            VStack(spacing: 16) {
                WhyReminderCard(reason: profile.primaryReason.payoff)
                if let note = profile.personalReasonText, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(note).font(.body).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .craving:
            VStack(spacing: 26) {
                Label("I WANT TO SMOKE", systemImage: "wind")
                    .font(.headline).padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(AppColor.surface.opacity(0.7), in: Capsule())
                    .overlay(Capsule().stroke(AppColor.sage, lineWidth: 1.25))
                Circle().fill(AppColor.forest.opacity(0.17))
                    .overlay(Circle().stroke(AppColor.sage.opacity(0.8), lineWidth: 2))
                    .overlay(Text("Breathe").font(.title2).foregroundStyle(AppColor.text))
                    .frame(width: 150, height: 150)
                    .scaleEffect(reduceMotion || appeared ? 1 : 0.9)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 2).repeatCount(2, autoreverses: true), value: appeared)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("The I WANT TO SMOKE action opens a guided breathing exercise.")
        case .keepWhatYouGained:
            ZStack {
                Circle().fill(RadialGradient(colors: [AppColor.forest.opacity(0.25), .clear], center: .center, startRadius: 15, endRadius: 120))
                VStack(spacing: 24) {
                    Image(systemName: "leaf").font(.system(size: 54, weight: .light))
                    HStack(spacing: 24) {
                        ForEach(["clock", "banknote", "photo", "wind"], id: \.self) { icon in
                            Image(systemName: icon).font(.title3)
                        }
                    }
                }.foregroundStyle(AppColor.sage)
            }.frame(height: 240).accessibilityHidden(true)
        }
    }

    private var timerPreview: some View {
        let duration = QuitCalculations.duration(since: profile.quitDate, now: now)
        return VStack(spacing: 8) {
            Text("You haven’t smoked for").font(.headline).foregroundStyle(AppColor.secondaryText)
            Text("\(duration.days) days").font(.system(size: 54, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6).lineLimit(1)
            Text("\(duration.hours) hours  \(duration.minutes) min").font(.title2.weight(.semibold))
                .foregroundStyle(AppColor.sage)
        }
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
    }

    private var gainsPreview: some View {
        VStack(spacing: 14) {
            WalkthroughStat(icon: "leaf.fill", title: "Cigarettes avoided", value: "\(QuitCalculations.cigarettesAvoided(profile: profile, now: now))")
            WalkthroughStat(icon: "banknote.fill", title: "Money saved", value: QuitCalculations.currency(QuitCalculations.moneySaved(profile: profile, now: now), code: profile.currencyCode))
        }
    }
}

private struct WalkthroughStat: View {
    let icon: String
    let title: String
    let value: String
    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: icon).font(.title2).foregroundStyle(AppColor.sage).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline).foregroundStyle(AppColor.secondaryText)
                Text(value).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(20).frame(maxWidth: .infinity)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .combine)
    }
}
