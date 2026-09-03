import SwiftUI

struct WhyReminderCard: View {
    let reason: String
    var showsChevron = false
    @AppStorage("whyPhotoRevision") private var photoRevision = ""

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let photo = WhyPhotoStore.load() {
                Image(uiImage: photo).resizable().scaledToFill()
                    .overlay(LinearGradient(colors: [.black.opacity(0.08), .black.opacity(0.78)], startPoint: .top, endPoint: .bottom))
            } else {
                LinearGradient(
                    colors: [AppColor.forest.opacity(0.18), AppColor.surface, AppColor.surface],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
            }
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Remember why you started.").font(.headline)
                    Text(reason).font(.title2.bold())
                }
                Spacer(minLength: 8)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.bottom, 5)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, 30)
            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
        }
        .id(photoRevision)
        .frame(maxWidth: .infinity, minHeight: 165, maxHeight: 175, alignment: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Remember why you started. \(reason)")
    }
}

struct WhyReminderSheet: View {
    let reason: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                if let photo = WhyPhotoStore.load() {
                    Image(uiImage: photo).resizable().scaledToFill().ignoresSafeArea()
                    LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.88)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                } else { AppColor.background.ignoresSafeArea() }
                VStack(spacing: 16) {
                    Spacer()
                    Text("Remember why you started.").font(.title2).foregroundStyle(.white.opacity(0.75))
                    Text(reason).font(.largeTitle.bold()).multilineTextAlignment(.center).foregroundStyle(.white)
                    Text("You chose yourself today.").foregroundStyle(AppColor.sage).padding(.top, 4)
                    Spacer()
                    PrimaryButton(title: "Keep going") { dismiss() }
                }.padding(24)
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() }.foregroundStyle(.white) } }
        }
    }
}
