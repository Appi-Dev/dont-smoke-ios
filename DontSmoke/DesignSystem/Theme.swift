import SwiftUI

enum AppColor {
    static let background = Color(red: 0.025, green: 0.09, blue: 0.075)
    static let surface = Color(red: 0.04, green: 0.14, blue: 0.11)
    static let forest = Color(red: 0.35, green: 0.78, blue: 0.32)
    static let sage = Color(red: 0.58, green: 0.90, blue: 0.42)
    static let text = Color.white
    static let secondaryText = Color.white.opacity(0.65)
    static let gold = Color(red: 0.82, green: 0.68, blue: 0.37)
    static let teal = Color(red: 0.18, green: 0.48, blue: 0.44)
    static let mist = surface
}

struct PrimaryButton: View {
    let title: String
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity).frame(minHeight: 52)
        }
        .buttonStyle(.plain).foregroundStyle(Color.black.opacity(0.8))
        .background(disabled ? AppColor.sage.opacity(0.45) : AppColor.sage, in: RoundedRectangle(cornerRadius: 16))
        .disabled(disabled).accessibilityHint(disabled ? "Complete the required fields first" : "")
    }
}

struct ChoiceCard: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { Text(title).multilineTextAlignment(.leading); Spacer(); Image(systemName: selected ? "checkmark.circle.fill" : "circle") }
                .font(.body.weight(.medium)).padding().frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(AppColor.text)
                .background(selected ? AppColor.forest.opacity(0.22) : AppColor.mist, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? AppColor.forest : .clear, lineWidth: 2))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct OnboardingShell<Content: View>: View {
    let step: Int
    let back: (() -> Void)?
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let back { Button(action: back) { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Back") }
                else { Color.clear.frame(width: 44, height: 44) }
                GeometryReader { proxy in
                    Capsule().fill(AppColor.mist).overlay(alignment: .leading) {
                        Capsule().fill(AppColor.sage).frame(width: proxy.size.width * CGFloat(step + 1) / 10)
                    }
                }.frame(height: 4).animation(.easeInOut, value: step)
                Color.clear.frame(width: 44, height: 44)
            }.padding(.horizontal)
            content
        }.background(AppColor.background.ignoresSafeArea()).foregroundStyle(AppColor.text)
    }
}

extension View {
    func screenTitle(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(title).font(.largeTitle.bold()).frame(maxWidth: .infinity, alignment: .leading); self }
    }
}
