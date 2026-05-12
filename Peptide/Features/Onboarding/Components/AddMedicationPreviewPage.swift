import SwiftUI

/// "Add Your First Medication" onboarding teaser. Shows three demo vials
/// on a stylised shelf so the user previews what their inventory will
/// look like — actual medication entry happens after onboarding completes
/// (the dashed placeholder reads "You'll add it right after onboarding").
struct AddMedicationPreviewPage: View {
    @State private var animateIn = false

    private let demos: [Demo] = [
        Demo(compound: "Retatrutide", labelText: "Retatrutide\n5 mg",  level: 0.85),
        Demo(compound: "Ipamorelin",  labelText: "KLOW\n10 mg",        level: 0.65),
        Demo(compound: "BPC-157",     labelText: "BPC-157\n5 mg",      level: 0.78),
    ]

    var body: some View {
        VStack(spacing: Spacing.xl) {
            VStack(spacing: Spacing.md) {
                Text("Add your first medication")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Add what you're running. PeptideX builds the schedule and tracks what's left in each vial.")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }

            shelf

            Text("You'll add it right after onboarding.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                animateIn = true
            }
        }
    }

    // MARK: - Shelf

    private var shelf: some View {
        ZStack(alignment: .bottom) {
            shelfPlatform

            HStack(alignment: .bottom, spacing: Spacing.md) {
                ForEach(Array(demos.enumerated()), id: \.offset) { index, demo in
                    VialIllustration(
                        compoundName: demo.compound,
                        liquidLevel: demo.level,
                        labelText: demo.labelText,
                        size: .md
                    )
                    .scaleEffect(animateIn ? 1 : 0.6)
                    .opacity(animateIn ? 1 : 0)
                    .animation(
                        .spring(response: 0.55, dampingFraction: 0.7).delay(Double(index) * 0.10),
                        value: animateIn
                    )
                }
            }
            .padding(.bottom, Spacing.sm)
        }
        .frame(maxWidth: .infinity)
    }

    /// Subtle shelf surface — a thin gradient capsule with a soft drop shadow
    /// underneath. Reads as a real shelf in front of the ambient backdrop
    /// instead of a floating tab.
    private var shelfPlatform: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            AppColor.surfaceElevated.opacity(0.95),
                            AppColor.surfaceSecondary.opacity(0.85),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 10)
                .overlay {
                    Capsule().strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }

            Capsule()
                .fill(Color.black.opacity(0.35))
                .frame(height: 3)
                .blur(radius: 3)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, 2)
        }
        .padding(.horizontal, Spacing.md)
    }

    private struct Demo {
        let compound: String
        let labelText: String
        let level: Double
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        AddMedicationPreviewPage()
            .padding(.horizontal, Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
