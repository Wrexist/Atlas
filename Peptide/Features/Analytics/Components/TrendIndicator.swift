import SwiftUI

struct TrendIndicator: View {
    let value: Double
    let label: LocalizedStringKey

    private var isPositive: Bool { value >= 0 }

    var body: some View {
        GlassCardCompact(tinted: isPositive) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isPositive ? AppColor.accentLight : AppColor.destructive)

                Text("\(isPositive ? "+" : "")\(Int(value * 100))%")
                    .font(AppFont.headline)
                    .foregroundStyle(isPositive ? AppColor.accentLight : AppColor.destructive)

                Text(label)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)

                Spacer()
            }
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.md) {
            TrendIndicator(value: 0.12, label: "compliance this month")
            TrendIndicator(value: -0.05, label: "compliance this week")
        }
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
