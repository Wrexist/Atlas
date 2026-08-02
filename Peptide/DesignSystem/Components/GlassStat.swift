import SwiftUI

struct GlassStat: View {
    let value: String
    let label: LocalizedStringKey
    var icon: String?
    var tinted: Bool = false

    var body: some View {
        GlassCardCompact(tinted: tinted) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(AppFont.scaled(12, weight: .semibold))
                        .foregroundStyle(tinted ? AppColor.accentLight : AppColor.textTertiary)
                }

                Text(value)
                    .font(AppFont.statValueSmall)
                    .foregroundStyle(tinted ? AppColor.accentLight : AppColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(label)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 100, alignment: .leading)
        }
    }
}

struct GlassStatPill: View {
    let value: String
    let label: LocalizedStringKey
    var icon: String?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(AppFont.scaled(12, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(value)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(label)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .glassSurface(cornerRadius: Spacing.smallCornerRadius)
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.lg) {
            HStack(spacing: Spacing.md) {
                GlassStat(value: "45", label: "Days Logged", icon: "calendar")
                GlassStat(value: "12", label: "Streak", icon: "flame.fill", tinted: true)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    GlassStatPill(value: "2", label: "Active", icon: "list.clipboard")
                    GlassStatPill(value: "45", label: "Days", icon: "calendar")
                    GlassStatPill(value: "12", label: "Streak", icon: "flame.fill")
                }
            }
        }
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
