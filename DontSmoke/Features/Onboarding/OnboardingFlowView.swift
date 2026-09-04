import SwiftUI
import SwiftData

struct OnboardingFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model = OnboardingViewModel()
    @State private var isFinishing = false
    var body: some View {
        OnboardingShell(step: model.step, back: model.step == 0 ? nil : { model.back() }) {
            ScrollView { Group {
                switch model.step {
                case 0: LastSmokeStep(model: model)
                case 1: DailyAmountStep(model: model)
                case 2: CostStep(model: model)
                case 3: WhyStep(model: model) { model.next() }
                case 4: TriggerStep(model: model, skip: { complete(.deferred) }) {
                    model.triggerTimes.isEmpty ? complete(.deferred) : model.next()
                }
                case 5: TriggerTimeStep(model: model) {
                    model.triggerTimes.isEmpty ? complete(.deferred) : model.next()
                }
                default: NotificationContextStep(isFinishing: isFinishing, notNow: { complete(.deferred) }) {
                    Task {
                        isFinishing = true
                        let permission = await NotificationService.scheduler.requestAuthorizationIfNeeded()
                        complete(permission == .authorized || permission == .provisional ? .enabled : .declined)
                    }
                }
                }
            }.padding(.horizontal, 24).padding(.bottom, 28).frame(maxWidth: 680) }.scrollDismissesKeyboard(.interactively)
        }
    }
    private func complete(_ notificationPreference: NotificationPreference) {
        guard !isFinishing || notificationPreference != .deferred else { return }
        guard let reason = model.primaryReason else { return }
        let profile = QuitProfile(quitDate: model.quitDate, cigarettesPerDay: model.cigarettesPerDay, packPrice: model.packPrice,
            packSize: model.packSize, currencyCode: model.currencyCode, primaryReason: reason, reasons: Array(model.reasons), personalReasonText: model.personalReasonText.nilIfBlank,
            triggers: Array(model.triggers), notificationPreference: notificationPreference)
        modelContext.insert(profile)
        let schedules = model.triggerTimes.map { trigger, time in
            let schedule = CravingSchedule(trigger: trigger, preferredTime: time, reminderEnabled: notificationPreference == .enabled)
            schedule.profile = profile; modelContext.insert(schedule); return schedule
        }
        try? modelContext.save()
        if notificationPreference == .enabled {
            Task { for schedule in schedules { await NotificationService.scheduler.scheduleReminder(id: schedule.id, trigger: schedule.trigger, cravingTime: schedule.preferredTime) } }
        }
    }
}

private struct LastSmokeStep: View {
    @Bindable var model: OnboardingViewModel
    var body: some View { VStack(alignment: .leading, spacing: 22) {
        Spacer(minLength: 36); Text("Don’t Smoke").font(.title3.bold()).foregroundStyle(AppColor.sage)
        Text("When did you last smoke?").font(.largeTitle.bold()); Text("This is where your progress begins.").foregroundStyle(AppColor.secondaryText)
        ChoiceCard(title: "Today", selected: model.dateChoice == 0) { model.chooseDate(0) }
        ChoiceCard(title: "Yesterday", selected: model.dateChoice == 1) { model.chooseDate(1) }
        ChoiceCard(title: "Choose date & time", selected: model.dateChoice == 2) { model.dateChoice = 2 }
        if model.dateChoice == 2 { DatePicker("Last smoked", selection: $model.quitDate, in: ...Date(), displayedComponents: [.date, .hourAndMinute]).datePickerStyle(.graphical).tint(AppColor.sage) }
        Text(model.quitDate.formatted(date: .long, time: .shortened)).font(.headline).foregroundStyle(AppColor.sage)
        PrimaryButton(title: "Continue") { model.next() }
    } }
}

private struct DailyAmountStep: View {
    @Bindable var model: OnboardingViewModel
    var body: some View { VStack(spacing: 26) {
        Spacer(minLength: 36); Text("About how many cigarettes a day?").font(.largeTitle.bold()).frame(maxWidth: .infinity, alignment: .leading)
        HStack(spacing: 28) {
            stepButton("minus", label: "Decrease") { model.cigarettesPerDay = max(1, model.cigarettesPerDay - 1) }
            VStack { Text("\(model.cigarettesPerDay)").font(.system(size: 72, weight: .bold, design: .rounded)); Text("per day").foregroundStyle(AppColor.secondaryText) }
            stepButton("plus", label: "Increase") { model.cigarettesPerDay += 1 }
        }
        HStack { ForEach([5, 10, 15, 20, 30], id: \.self) { number in Button(number == 30 ? "30+" : "\(number)") { model.cigarettesPerDay = number }.buttonStyle(.bordered).buttonBorderShape(.capsule).tint(AppColor.sage) } }
        Text("We’ll use this only to calculate what you’ve gained.").font(.footnote).foregroundStyle(AppColor.secondaryText)
        PrimaryButton(title: "Continue") { model.next() }
    } }
    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View { Button(action: action) { Image(systemName: symbol).frame(width: 52, height: 52) }.buttonStyle(.bordered).tint(AppColor.sage).accessibilityLabel(label) }
}

private struct CostStep: View {
    @Bindable var model: OnboardingViewModel
    var body: some View { VStack(alignment: .leading, spacing: 22) {
        Spacer(minLength: 36); Text("What did smoking usually cost?").font(.largeTitle.bold()); Text("Enter the pack price and size.").foregroundStyle(AppColor.secondaryText)
        Picker("Currency", selection: $model.currencyCode) {
            ForEach(CurrencySupport.availableCodes, id: \.self) { code in
                Text(CurrencySupport.pickerLabel(for: code)).tag(code)
            }
        }
        .pickerStyle(.menu)
        .tint(AppColor.sage)
        HStack { Text(CurrencySupport.symbol(for: model.currencyCode)).font(.title.bold()); TextField("200", text: $model.packPriceText).font(.title.bold()).keyboardType(.decimalPad) }.padding().background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16)).accessibilityElement(children: .combine).accessibilityLabel("Pack price in \(CurrencySupport.name(for: model.currencyCode))")
        Stepper("Cigarettes in a pack: \(model.packSize)", value: $model.packSize, in: 1...100).padding().background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
        VStack(alignment: .leading, spacing: 6) { Text("\(QuitCalculations.currency(QuitCalculations.costPerCigarette(packPrice: model.packPrice, packSize: model.packSize), code: model.currencyCode)) per cigarette"); Text("About \(QuitCalculations.currency(model.dailySpend, code: model.currencyCode)) each day").font(.title2.bold()).foregroundStyle(AppColor.sage) }.padding(.vertical)
        PrimaryButton(title: "Continue", disabled: !model.canContinue) { model.next() }
    } }
}

private struct WhyStep: View {
    @Bindable var model: OnboardingViewModel; let complete: () -> Void
    private let reasons: [(QuitReason, String)] = [(.children, "My kids"), (.health, "My health"), (.money, "Save money"), (.fitness, "Better fitness"), (.family, "Better sleep"), (.partner, "No smell"), (.other, "Custom reason")]
    var body: some View { VStack(alignment: .leading, spacing: 14) {
        Spacer(minLength: 24); Text("Why do you want to quit?").font(.largeTitle.bold()); Text("Choose the reason you want to remember.").foregroundStyle(AppColor.secondaryText).padding(.bottom, 8)
        ForEach(reasons, id: \.0) { reason, title in ChoiceCard(title: title, selected: model.primaryReason == reason) { model.reasons = [reason]; model.primaryReason = reason } }
        if model.primaryReason == .other { TextField("Your reason", text: $model.personalReasonText).textFieldStyle(.roundedBorder).padding(.top, 6) }
        Text("Keep what you’ve gained.").font(.headline).foregroundStyle(AppColor.sage).padding(.vertical, 10)
        PrimaryButton(title: "Continue", disabled: model.primaryReason == nil || (model.primaryReason == .other && model.personalReasonText.nilIfBlank == nil), action: complete)
    } }
}

private struct TriggerStep: View {
    @Bindable var model: OnboardingViewModel
    let skip: () -> Void
    let next: () -> Void
    var body: some View { VStack(alignment: .leading, spacing: 14) {
        Spacer(minLength: 24)
        Text("When do cravings usually hit?").font(.largeTitle.bold())
        Text("We can remind you a little before your usual difficult moments.").foregroundStyle(AppColor.secondaryText).padding(.bottom, 8)
        ForEach(CravingTrigger.allCases) { trigger in
            ChoiceCard(title: trigger.title, selected: model.triggers.contains(trigger)) { model.toggleTrigger(trigger) }
        }
        PrimaryButton(title: "Continue", action: next)
        Button("Skip for now", action: skip).frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(AppColor.secondaryText)
    } }
}

private struct TriggerTimeStep: View {
    @Bindable var model: OnboardingViewModel
    let next: () -> Void
    var body: some View { VStack(alignment: .leading, spacing: 18) {
        Spacer(minLength: 24)
        Text("Choose an approximate time").font(.largeTitle.bold())
        Text("Only triggers with a time can send a reminder. You can change these later.").foregroundStyle(AppColor.secondaryText)
        ForEach(model.triggers.sorted { $0.rawValue < $1.rawValue }) { trigger in
            VStack(alignment: .leading, spacing: 10) {
                Toggle(trigger.title, isOn: Binding(get: { model.triggerTimes[trigger] != nil }, set: { model.setTimed($0, for: trigger) }))
                    .tint(AppColor.sage)
                if let time = model.triggerTimes[trigger] {
                    DatePicker(trigger.timingQuestion, selection: Binding(get: { time }, set: { model.triggerTimes[trigger] = $0 }), displayedComponents: .hourAndMinute)
                        .tint(AppColor.sage)
                } else if !trigger.predictable {
                    Text("Saved without a reminder time.").font(.footnote).foregroundStyle(AppColor.secondaryText)
                }
            }.padding().background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        PrimaryButton(title: "Continue", action: next)
    } }
}

private struct NotificationContextStep: View {
    let isFinishing: Bool
    let notNow: () -> Void
    let enable: () -> Void
    var body: some View { VStack(spacing: 22) {
        Spacer(minLength: 70)
        Image(systemName: "bell.badge").font(.system(size: 48, weight: .light)).foregroundStyle(AppColor.sage)
        Text("Want a little support before cravings usually hit?").font(.largeTitle.bold()).multilineTextAlignment(.center)
        Text("We can send a calm reminder a few minutes beforehand.").foregroundStyle(AppColor.secondaryText).multilineTextAlignment(.center)
        Spacer(minLength: 30)
        PrimaryButton(title: isFinishing ? "Enabling…" : "Enable reminders", disabled: isFinishing, action: enable)
        Button("Not now", action: notNow).disabled(isFinishing).frame(minHeight: 44).foregroundStyle(AppColor.secondaryText)
    } }
}

private extension String { var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self } }
