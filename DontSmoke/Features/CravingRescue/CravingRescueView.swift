import SwiftUI

struct CravingRescueView: View {
    let profile: QuitProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session: RescueSession
    @State private var audioService = RescueAudioService()

    init(profile: QuitProfile, entitlements: any RescueEntitlementProviding = DefaultRescueEntitlements()) {
        self.profile = profile
        _session = State(initialValue: RescueSession(
            access: entitlements.rescueAccess,
            lastRandomSound: RescueAudioService.lastRandomSound
        ))
    }

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    Group {
                        switch session.phase {
                        case .grounding: groundingContent
                        case .breathing, .continuedBreathing, .extended: breathingContent
                        case .checkIn: checkInContent
                        case .myWhy: whyContent
                        case .settling, .completed: completionContent
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 610)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .foregroundStyle(AppColor.text)
        }
        .task {
            RescueAudioService.lastRandomSound = session.selectedSound
            updateAudio()
            while !Task.isCancelled {
                session.update(now: .now)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        .onChange(of: session.selectedSound) { _, _ in updateAudio() }
        .onChange(of: session.isMuted) { _, _ in updateAudio() }
        .onDisappear { audioService.stop() }
    }

    private var topBar: some View {
        HStack {
            soundMenu
            Spacer()
            Button("Close") { dismiss() }
                .frame(minWidth: 44, minHeight: 44)
                .foregroundStyle(AppColor.secondaryText)
                .accessibilityHint("Closes the craving rescue session.")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var soundMenu: some View {
        Menu {
            Button {
                session.select(.random)
                RescueAudioService.lastRandomSound = session.selectedSound
            } label: {
                menuLabel("Random", selected: session.soundSelection == .random)
            }
            ForEach(session.access.availableSoundscapes) { soundscape in
                Button { session.select(.soundscape(soundscape)) } label: {
                    menuLabel(soundscape.title, selected: session.soundSelection == .soundscape(soundscape))
                }
            }
            if session.selectedSound != .silence {
                Divider()
                Button(session.isMuted ? "Turn Sound On" : "Mute") { session.toggleMute() }
            }
        } label: {
            Image(systemName: session.isMuted || session.selectedSound == .silence ? "speaker.slash" : "speaker.wave.2")
                .frame(width: 44, height: 44)
                .foregroundStyle(AppColor.sage)
                .background(AppColor.surface, in: Circle())
        }
        .accessibilityLabel("Ambient sound")
        .accessibilityValue(soundAccessibilityValue)
        .accessibilityHint("Choose or mute the calming background sound.")
    }

    private func menuLabel(_ title: String, selected: Bool) -> some View {
        Label(title, systemImage: selected ? "checkmark" : "circle")
    }

    private var groundingContent: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "wind")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(AppColor.sage)
            Text("The craving is here.\nYou don’t have to act on it.")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Stay with me for a few minutes.")
                .font(.title3)
                .foregroundStyle(AppColor.secondaryText)
                .multilineTextAlignment(.center)
            Spacer()
            Text("Let your shoulders soften.")
                .foregroundStyle(AppColor.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private var breathingContent: some View {
        let breathing = session.breathingPhase
        return VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text(session.phase == .extended ? "Stay with this moment." : "The craving will pass.")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text("Follow your breath.").foregroundStyle(AppColor.secondaryText)
            }
            Spacer(minLength: 20)
            ZStack {
                Circle()
                    .fill(AppColor.forest.opacity(reduceMotion ? (breathing == .exhale ? 0.10 : 0.20) : 0.17))
                    .frame(
                        width: reduceMotion ? 220 : breathing.circleSize,
                        height: reduceMotion ? 220 : breathing.circleSize
                    )
                    .overlay(Circle().stroke(AppColor.sage.opacity(0.8), lineWidth: 2))
                    .animation(reduceMotion ? .easeInOut(duration: 0.4) : .easeInOut(duration: breathing.duration), value: breathing)
                VStack(spacing: 4) {
                    Text(breathing.title).font(.title.bold())
                    Text("\(session.breathingSecondsRemaining)")
                        .font(.system(size: 50, weight: .light, design: .rounded))
                    Text("seconds").foregroundStyle(AppColor.secondaryText)
                }
            }
            .frame(height: 290)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(breathing.title), \(session.breathingSecondsRemaining) seconds")
            Spacer(minLength: 20)
            Text("One choice at a time.").foregroundStyle(AppColor.secondaryText)
        }
    }

    private var checkInContent: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "leaf")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(AppColor.sage)
            Text("Is it getting a little easier?")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)
            PrimaryButton(title: "A little") { session.answerCheckIn(isEasier: true) }
            Button { session.answerCheckIn(isEasier: false) } label: {
                Text("Not yet")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColor.sage.opacity(0.7)))
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private var whyContent: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)
            WhyReminderCard(reason: profile.primaryReason.payoff)
            if let note = profile.personalReasonText, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(note).font(.title3).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            Text("You gave yourself time instead of reacting.")
                .font(.title3)
                .foregroundStyle(AppColor.secondaryText)
                .multilineTextAlignment(.center)
            Spacer()
            PrimaryButton(title: session.access.sessionDuration > RescueSession.checkInTime ? "Keep breathing" : "Continue") {
                session.continueAfterWhy()
            }
        }
    }

    private var completionContent: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(AppColor.sage)
            Text(completionTitle)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("You gave yourself time instead of reacting.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColor.secondaryText)
            Spacer()
            PrimaryButton(title: "I’m okay now") { dismiss() }
            if session.canExtend && session.phase == .completed {
                Button("Stay with me another 5 minutes") { session.startExtension(at: .now) }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(AppColor.sage)
                    .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var completionTitle: String {
        if session.phase == .settling { return "Let your breathing settle." }
        if session.extensionUsed { return "You stayed with it a little longer." }
        return session.access.canExtend
            ? "You made it through these five minutes."
            : "You made it through these two minutes."
    }

    private var soundAccessibilityValue: String {
        if session.isMuted || session.selectedSound == .silence { return "Silence" }
        return session.selectedSound?.title ?? "Silence"
    }

    private func updateAudio() {
        audioService.play(session.selectedSound, muted: session.isMuted)
    }
}
