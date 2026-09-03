import SwiftUI

struct CravingRescueView: View {
    let profile: QuitProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = BreathingPhase.inhale
    @State private var secondsLeft = 4
    @State private var cycleComplete = false
    @State private var showWhy = false

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()
            VStack(spacing: 24) {
                HStack { Spacer(); Button("Close") { dismiss() }.frame(minHeight: 44).foregroundStyle(AppColor.secondaryText) }
                Text("The craving will pass.").font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text("Stay with me for a minute.").font(.title3).foregroundStyle(AppColor.secondaryText)
                Spacer()
                ZStack {
                    Circle().fill(AppColor.forest.opacity(0.15)).frame(width: reduceMotion ? 220 : phase.circleSize, height: reduceMotion ? 220 : phase.circleSize)
                        .overlay(Circle().stroke(AppColor.sage.opacity(0.8), lineWidth: 2)).animation(reduceMotion ? nil : .easeInOut(duration: Double(phase.duration)), value: phase)
                    VStack { Text(phase.title).font(.title.bold()); Text("\(secondsLeft)").font(.system(size: 50, weight: .light, design: .rounded)); Text("seconds").foregroundStyle(AppColor.secondaryText) }
                }.accessibilityElement(children: .combine).accessibilityLabel("\(phase.title), \(secondsLeft) seconds")
                Spacer()
                if cycleComplete {
                    Text("Still want to smoke?").font(.title2.bold())
                    PrimaryButton(title: "Give me another minute") { restart() }
                    Button("Remind me why I quit") { showWhy = true }.frame(minHeight: 44).foregroundStyle(AppColor.sage)
                    Button("I’m okay now") { dismiss() }.frame(minHeight: 44).foregroundStyle(AppColor.text)
                } else { Text("One choice at a time.").foregroundStyle(AppColor.secondaryText) }
            }.padding(24).foregroundStyle(AppColor.text)
        }
        .task { await runCycle() }
        .sheet(isPresented: $showWhy) { WhyReminderSheet(reason: profile.personalReasonText ?? profile.primaryReason.payoff) }
    }

    private func runCycle() async {
        for next in BreathingPhase.allCases {
            guard !Task.isCancelled else { return }
            phase = next; secondsLeft = next.duration
            for remaining in stride(from: next.duration, through: 1, by: -1) { secondsLeft = remaining; try? await Task.sleep(for: .seconds(1)) }
        }
        cycleComplete = true
    }
    private func restart() { cycleComplete = false; Task { await runCycle() } }
}

private enum BreathingPhase: CaseIterable {
    case inhale, hold, exhale
    var title: String { switch self { case .inhale: "Breathe in"; case .hold: "Hold"; case .exhale: "Breathe out" } }
    var duration: Int { switch self { case .inhale: 4; case .hold: 2; case .exhale: 6 } }
    var circleSize: CGFloat { switch self { case .inhale: 280; case .hold: 280; case .exhale: 190 } }
}
