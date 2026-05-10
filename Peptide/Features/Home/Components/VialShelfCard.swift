import SwiftUI

/// Horizontal scroll of vials representing the user's active stack —
/// surfaced on the Home tab between the schedule card and the quick
/// stats row. Caps at four entries so the row stays readable on small
/// screens; if the stack is empty, the card hides itself entirely.
///
/// `liquidLevel` per peptide is currently a static `1.0` placeholder —
/// real per-vial inventory tracking (mg-per-dose, doses-logged, refill
/// state) doesn't exist in the data model yet. Hooking the level up to
/// real consumption is a separate task; the spec'd 800 ms drain
/// animation is wired inside `VialIllustration` so it Just Works once
/// the level is driven from real data.
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
                                VialIllustration(
                                    compoundName: peptide.name,
                                    liquidLevel: 1.0,
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
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppColor.accentLight)
            Text("YOUR INVENTORY")
                .font(.system(size: 11, weight: .heavy))
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
