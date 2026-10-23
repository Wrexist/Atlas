import SwiftUI

/// Horizontal scroll of vials representing the compounds in the user's
/// active protocols. Caps at four entries so the row stays readable on
/// small screens; if there are none, the card hides itself entirely.
///
/// The vials are illustrations, not inventory: Atlas doesn't know the
/// user's vial size, reconstitution or purchases, so every vial is drawn
/// full rather than with a level that could be read as "what's left".
struct VialShelfCard: View {
    let peptides: [Peptide]

    private static let maxVials = 4

    private var displayed: [Peptide] {
        Array(peptides.prefix(Self.maxVials))
    }

    var body: some View {
        if displayed.isEmpty {
            EmptyView()
        } else {
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    header

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: Spacing.lg) {
                            ForEach(displayed) { peptide in
                                CompoundVial(
                                    compoundName: peptide.name,
                                    category: peptide.category,
                                    labelText: peptide.abbreviation,
                                    size: .md
                                )
                            }
                        }
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xs)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "flask.fill")
                .font(AppFont.scaled(13, weight: .bold))
                .foregroundStyle(AppColor.accentLight)
                .accessibilityHidden(true)
            Text("Your protocol compounds")
                .font(AppFont.eyebrow)
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.textSecondary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            if peptides.count > Self.maxVials {
                Text("+\(peptides.count - Self.maxVials)")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }
}
