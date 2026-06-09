import SwiftUI

/// Eyebrow + title pair that breaks the merged Today scroll into
/// legible chunks (Doses / Meals / Wellness / Movement / Stack /
/// Smart suggestions). Phase 33 lifted this out of the now-deleted
/// `LifestyleView.sectionHeader` so every Today section consumes
/// one source of truth and the visual language stays consistent.
///
/// The trailing-slot generic lets a section like "Nutrition" hang
/// an inline "Edit targets" button on the right without forking
/// the API for the simple no-trailing case.
struct HomeSectionHeader<Trailing: View>: View {
    let eyebrow: LocalizedStringKey
    let title: LocalizedStringKey
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.accentLight.opacity(0.85))
                Text(title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.top, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        // Header trait so VoiceOver's heading rotor can jump between
        // Today sections on the long merged scroll (Deep Audit II C15).
        .accessibilityAddTraits(.isHeader)
    }
}

extension HomeSectionHeader where Trailing == EmptyView {
    init(eyebrow: LocalizedStringKey, title: LocalizedStringKey) {
        self.init(eyebrow: eyebrow, title: title) { EmptyView() }
    }
}
