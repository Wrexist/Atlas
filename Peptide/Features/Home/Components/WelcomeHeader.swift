import SwiftUI

struct WelcomeHeader: View {
    let greeting: String
    let name: String
    let date: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if name.isEmpty {
                    Text(greeting)
                        .font(AppFont.largeTitle)
                        .foregroundStyle(AppColor.textPrimary)
                } else {
                    Text("\(greeting),")
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.textPrimary)

                    Text(name)
                        .font(AppFont.largeTitle)
                        .foregroundStyle(AppColor.accentLight)
                }

                Text(date)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(AppColor.accentPrimary.opacity(0.2))
                    .frame(width: 52, height: 52)
                    .overlay {
                        Circle()
                            .strokeBorder(AppColor.glassBorderActive, lineWidth: 1)
                    }

                if name.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(AppColor.accentLight)
                } else {
                    Text(String(name.prefix(1)))
                        .font(AppFont.title2)
                        .foregroundStyle(AppColor.accentLight)
                }
            }
            .glassEffect(in: .circle)
        }
        .padding(.top, Spacing.sm)
    }
}

#Preview("With Name") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        WelcomeHeader(greeting: "Good evening", name: "Alex", date: "Thursday, April 10")
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}

#Preview("No Name") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        WelcomeHeader(greeting: "Good evening", name: "", date: "Thursday, April 10")
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
