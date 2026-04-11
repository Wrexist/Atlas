import SwiftUI

struct ProtocolScoreCard: View {
    let score: Double
    let completed: Int
    let total: Int

    var body: some View {
        GlassCard(tinted: true) {
            VStack(spacing: Spacing.lg) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("PROTOCOL SCORE")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .tracking(1.5)

                        Text("Today's Progress")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                    }

                    Spacer()

                    Text("\(completed)/\(total)")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }

                GlassProgressRing(progress: score, size: 180, lineWidth: 14)
                    .frame(height: 180)

                GlassProgressBar(progress: score)
                    .padding(.horizontal, Spacing.xl)
            }
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        ProtocolScoreCard(score: 0.75, completed: 3, total: 4)
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
