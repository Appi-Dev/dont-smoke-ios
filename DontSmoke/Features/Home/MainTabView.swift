import SwiftUI
import PhotosUI

struct MainTabView: View {
    let profile: QuitProfile
    @State private var selectedTab = AppTab.today

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(profile: profile) { selectedTab = .me }
                .tabItem { Label("Today", systemImage: "sun.max.fill") }.tag(AppTab.today)
            ProgressViewScreen(profile: profile)
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }.tag(AppTab.progress)
            MeView(profile: profile)
                .tabItem { Label("Me", systemImage: "person.fill") }.tag(AppTab.me)
        }
        .tint(AppColor.sage)
        .toolbarBackground(AppColor.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

private enum AppTab: Hashable { case today, progress, me }

private struct TodayView: View {
    let profile: QuitProfile
    let editWhy: () -> Void
    @State private var showRescue = false
    @AppStorage("showMyWhyOnToday") private var showMyWhyOnToday = true
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let duration = QuitCalculations.duration(since: profile.quitDate, now: context.date)
                let avoided = QuitCalculations.cigarettesAvoided(profile: profile, now: context.date)
                let saved = QuitCalculations.moneySaved(profile: profile, now: context.date)
                ScrollView {
                    VStack(spacing: 28) {
                        VStack(spacing: 8) {
                            Text("You haven’t smoked for").font(.headline).foregroundStyle(AppColor.secondaryText)
                            VStack(spacing: 0) {
                                Text("\(duration.days) days").font(.system(size: 58, weight: .bold, design: .rounded))
                                Text("\(duration.hours) hours  \(duration.minutes) min").font(.title2.weight(.semibold)).foregroundStyle(AppColor.sage)
                            }.accessibilityElement(children: .combine)
                        }.padding(.top, 36)
                        Button { showRescue = true } label: {
                            Label("I WANT TO SMOKE", systemImage: "wind")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .background(AppColor.surface.opacity(0.7), in: Capsule())
                                .overlay(Capsule().stroke(AppColor.sage, lineWidth: 1.25))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Get help with a smoking craving")
                        .accessibilityHint("Opens the craving rescue exercise.")
                        HStack(spacing: 10) {
                            StatCard(icon: "leaf.fill", value: "\(avoided)", title: "Cigarettes\navoided")
                            StatCard(icon: "banknote.fill", value: QuitCalculations.currency(saved, code: profile.currencyCode), title: "Money\nsaved")
                            StatCard(icon: "clock.fill", value: "\(duration.totalHours)", title: "Smoke-free\nhours")
                        }
                        if showMyWhyOnToday {
                            Button(action: editWhy) {
                                WhyReminderCard(reason: profile.personalReasonText ?? profile.primaryReason.payoff, showsChevron: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Your reason for quitting. Tap to edit.")
                            .accessibilityHint(profile.personalReasonText ?? profile.primaryReason.payoff)
                        }
                    }
                    .padding(40)
                    .padding(.bottom, 24)
                    .frame(minHeight: 700, alignment: .top)
                }
            }
            .background(AppColor.background.ignoresSafeArea()).foregroundStyle(AppColor.text)
            .navigationTitle("Don’t Smoke").navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showRescue) { CravingRescueView(profile: profile) }
        }
    }
}

private struct StatCard: View {
    let icon: String; let value: String; let title: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(AppColor.sage)
            Text(value).font(.title3.bold()).minimumScaleFactor(0.65).lineLimit(1)
            Text(title).font(.caption).foregroundStyle(AppColor.secondaryText).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, minHeight: 126).padding(.horizontal, 4).background(AppColor.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct ProgressViewScreen: View {
    let profile: QuitProfile
    var body: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 18) {
            Text("You’ve already gained this much.").font(.largeTitle.bold())
            progressCard("Cigarettes avoided", "\(QuitCalculations.cigarettesAvoided(profile: profile))", "leaf.fill")
            progressCard("Money saved", QuitCalculations.currency(QuitCalculations.moneySaved(profile: profile), code: profile.currencyCode), "banknote.fill")
            progressCard("Smoke-free hours", "\(QuitCalculations.duration(since: profile.quitDate).totalHours)", "clock.fill")
        }.padding(20) }.background(AppColor.background.ignoresSafeArea()).foregroundStyle(AppColor.text).navigationTitle("Progress") }
    }
    private func progressCard(_ title: String, _ value: String, _ icon: String) -> some View { HStack { Image(systemName: icon).font(.title).foregroundStyle(AppColor.sage).frame(width: 52); VStack(alignment: .leading) { Text(title).foregroundStyle(AppColor.secondaryText); Text(value).font(.title.bold()) }; Spacer() }.padding().background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20)) }
}

private struct MeView: View {
    @Bindable var profile: QuitProfile
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("whyPhotoRevision") private var photoRevision = ""
    @AppStorage("showMyWhyOnToday") private var showMyWhyOnToday = true
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoError: String?
    var body: some View {
        NavigationStack { Form {
            Section("My Why") {
                WhyReminderCard(reason: profile.personalReasonText ?? profile.primaryReason.payoff)
                PhotosPicker(selection: $selectedPhoto, matching: .images) { Label(WhyPhotoStore.load() == nil ? "Choose reminder photo" : "Change reminder photo", systemImage: "photo") }
                if WhyPhotoStore.load() != nil { Button("Remove reminder photo", role: .destructive) { removePhoto() } }
                Toggle("Show on Today", isOn: $showMyWhyOnToday)
                if let photoError { Text(photoError).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Quit settings") {
                LabeledContent("Last smoked", value: profile.quitDate.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Cigarettes per day", value: "\(profile.cigarettesPerDay)")
                LabeledContent("Pack cost", value: QuitCalculations.currency(profile.packPrice, code: profile.currencyCode))
                LabeledContent("Pack size", value: "\(profile.packSize)")
                Picker("Currency", selection: $profile.currencyCode) {
                    ForEach(CurrencySupport.availableCodes, id: \.self) { code in
                        Text(CurrencySupport.pickerLabel(for: code)).tag(code)
                    }
                }
            }
            Section("Preferences") { Toggle("Notifications", isOn: $notificationsEnabled); LabeledContent("Appearance", value: "Dark") }
        }.scrollContentBackground(.hidden).background(AppColor.background).navigationTitle("Me")
            .onChange(of: selectedPhoto) { _, item in Task { await importPhoto(item) } }
        }
    }

    private func importPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            try WhyPhotoStore.save(data); photoRevision = UUID().uuidString; photoError = nil
        } catch { photoError = "That photo couldn’t be saved. Please try another." }
    }

    private func removePhoto() {
        do { try WhyPhotoStore.remove(); photoRevision = UUID().uuidString; photoError = nil }
        catch { photoError = "The photo couldn’t be removed." }
    }
}
