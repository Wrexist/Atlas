import SwiftUI

struct WelcomeHeader: View {
    let greeting: String
    let name: String
    let date: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("\(greeting),")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)

                Text(name)
                    .font(AppFont.largeTitle)
                    .foregroundStyle(AppColor.accentLight)

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

                Text(String(name.prefix(1)))
                    .font(AppFont.title2)
                    .foregroundStyle(AppColor.accentLight)
            }
            .glassEffect(in: .circle)
        }
        .padding(.top, Spacing.sm)
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        WelcomeHeader(greeting: "Good evening", name: "Alex", date: "Thursday, April 10")
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
