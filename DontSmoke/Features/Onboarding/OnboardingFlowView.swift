import SwiftUI
import SwiftData

struct OnboardingFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model = OnboardingViewModel()
    var body: some View {
        OnboardingShell(step: model.step * 2 + 1, back: model.step == 0 ? nil : { model.back() }) {
            ScrollView { Group {
                switch model.step {
                case 0: LastSmokeStep(model: model)
                case 1: DailyAmountStep(model: model)
                case 2: CostStep(model: model)
                default: WhyStep(model: model, complete: complete)
                }
            }.padding(.horizontal, 24).padding(.bottom, 28).frame(maxWidth: 680) }.scrollDismissesKeyboard(.interactively)
        }
    }
    private func complete() {
        guard let reason = model.primaryReason else { return }
        let profile = QuitProfile(quitDate: model.quitDate, cigarettesPerDay: model.cigarettesPerDay, packPrice: model.packPrice,
            packSize: model.packSize, currencyCode: model.currencyCode, primaryReason: reason, reasons: Array(model.reasons), personalReasonText: model.personalReasonText.nilIfBlank,
            triggers: [], notificationPreference: .notAsked)
        modelContext.insert(profile); try? modelContext.save()
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
        PrimaryButton(title: "Start my smoke-free life", disabled: model.primaryReason == nil || (model.primaryReason == .other && model.personalReasonText.nilIfBlank == nil), action: complete)
    } }
}

private extension String { var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self } }
