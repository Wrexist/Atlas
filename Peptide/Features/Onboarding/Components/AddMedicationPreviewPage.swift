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
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.sm) {
                Text("Add Your First Medication")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Start by adding the medication you plan to use. Once it's in PeptideX, you can create schedules and track what's left.")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }

            shelf
                .padding(.top, Spacing.md)

            placeholderRow

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
                    .scaleEffect(animateIn ? 1 : 0.4)
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

    private var shelfPlatform: some View {
        Capsule()
            .fill(AppColor.surfaceSecondary.opacity(0.5))
            .frame(height: 14)
            .overlay {
                Capsule()
                    .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
            }
            .padding(.horizontal, Spacing.lg)
    }

    private var placeholderRow: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppColor.textSecondary)
            Text("Add Medication")
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    AppColor.glassBorder,
                    style: StrokeStyle(lineWidth: 1.0, dash: [5, 4])
                )
        }
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
