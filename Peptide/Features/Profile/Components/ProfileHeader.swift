import SwiftUI

struct ProfileHeader: View {
    let name: String
    let memberDuration: String

    var body: some View {
        GlassCard(tinted: true) {
            VStack(spacing: Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(AppColor.accentPrimary.opacity(0.2))
                        .frame(width: 80, height: 80)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [AppColor.accentLight, AppColor.accentPrimary],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        }

                    Text(String(name.prefix(1)))
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.accentLight)
                }
                .glassEffect(in: .circle)

                VStack(spacing: Spacing.xs) {
                    Text(name)
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.textPrimary)

                    Text("Member for \(memberDuration)")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }

                HStack(spacing: Spacing.xxl) {
                    ProfileStat(value: "4", label: "Protocols")
                    ProfileStat(value: "14", label: "Peptides")
                    ProfileStat(value: "45", label: "Days")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ProfileStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: Spacing.xxs) {
            Text(value)
                .font(AppFont.title2)
                .foregroundStyle(AppColor.accentLight)
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        ProfileHeader(name: "Alex", memberDuration: "3 months")
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
