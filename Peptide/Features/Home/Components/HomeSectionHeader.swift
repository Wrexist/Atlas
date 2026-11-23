import SwiftUI

/// Section title, with an optional eyebrow above it, that breaks the merged Today scroll into
/// legible chunks (Doses / Meals / Wellness / Movement / Stack /
/// Smart suggestions). Phase 33 lifted this out of the now-deleted
/// `LifestyleView.sectionHeader` so every Today section consumes
/// one source of truth and the visual language stays consistent.
///
/// The trailing-slot generic lets a section like "Nutrition" hang
/// an inline "Edit targets" button on the right without forking
/// the API for the simple no-trailing case.
struct HomeSectionHeader<Trailing: View>: View {
    /// Today's sections leave it out: one plain title per section reads
    /// faster than an eyebrow restating the title above it.
    let eyebrow: LocalizedStringKey?
    let title: LocalizedStringKey
    /// One line under the title saying what the section draws on
    /// (Biology's cards use it).
    let subtitle: LocalizedStringKey?
    let trailing: () -> Trailing

    init(
        eyebrow: LocalizedStringKey? = nil,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if let eyebrow {
                    HStack(spacing: Spacing.sm) {
                        AccentMarker()
                        Text(eyebrow)
                            .font(AppFont.footnote.weight(.medium))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                Text(title)
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(AppColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            // The eyebrow and title are one heading; the trailing action
            // stays its own stop so VoiceOver can still reach it.
            .accessibilityElement(children: .combine)
            // Header trait so VoiceOver's heading rotor can jump between
            // Today sections on the long merged scroll (Deep Audit II C15).
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            // Short counters and actions; the title wraps instead.
            trailing()
                .fixedSize()
        }
        .padding(.top, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension HomeSectionHeader where Trailing == EmptyView {
    init(eyebrow: LocalizedStringKey? = nil, title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) { EmptyView() }
    }
}
