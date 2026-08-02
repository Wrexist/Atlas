import SwiftUI

/// Horizontal scroll of vials representing the user's active stack —
/// surfaced on the Home tab between the schedule card and the quick
/// stats row. Caps at four entries so the row stays readable on small
/// screens; if the stack is empty, the card hides itself entirely.
///
/// Liquid level for each compound is now derived from
/// `DataStore.liquidLevel(for:)` which counts completed entries and
/// wraps modulo a default 30-doses-per-vial. The spec'd 800 ms drain
/// animation inside `CompoundVial` reacts to that fraction changing,
/// so the next dose log visibly nudges the meniscus down.
struct VialShelfCard: View {
    @Environment(DataStore.self) private var dataStore
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
                                    liquidLevel: dataStore.liquidLevel(for: peptide),
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
            Image(systemName: "tray.full.fill")
                .font(AppFont.scaled(13, weight: .bold))
                .foregroundStyle(AppColor.accentLight)
            Text("YOUR INVENTORY")
                .font(AppFont.scaled(11, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(AppColor.accentLight)

            Spacer(minLength: 0)

            if peptides.count > Self.maxVials {
                Text("+\(peptides.count - Self.maxVials)")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }
}
