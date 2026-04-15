import SwiftUI

struct ProfileHeader: View {
    let name: String
    let memberDuration: String
    let protocolCount: Int
    let peptideCount: Int
    let daysLogged: Int

    private var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : trimmed
    }

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

                    if displayName.isEmpty {
                        Image(systemName: "person.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(AppColor.accentLight)
                    } else {
                        Text(String(displayName.prefix(1)))
                            .font(AppFont.title)
                            .foregroundStyle(AppColor.accentLight)
                    }
                }
                .glassEffect(in: .circle)

                VStack(spacing: Spacing.xs) {
                    Text(displayName.isEmpty ? "PeptideX User" : displayName)
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.textPrimary)

                    Text("Member for \(memberDuration)")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }

                HStack(spacing: Spacing.xxl) {
                    ProfileStat(value: "\(protocolCount)", label: "Protocols")
                    ProfileStat(value: "\(peptideCount)", label: "Peptides")
                    ProfileStat(value: "\(daysLogged)", label: "Days")
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

#Preview("With Name") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        ProfileHeader(name: "Alex", memberDuration: "3 months", protocolCount: 4, peptideCount: 14, daysLogged: 45)
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}

#Preview("New User") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        ProfileHeader(name: "", memberDuration: "1 month", protocolCount: 0, peptideCount: 0, daysLogged: 0)
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
