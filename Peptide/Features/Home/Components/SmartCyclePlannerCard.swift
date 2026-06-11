import SwiftUI

/// Surfaces `SmartCyclePlanner.suggestions(...)` on the Home tab as a
/// stack of compact tip rows. Hides itself when the engine returns
/// nothing, or when every available suggestion is below `.medium`
/// confidence — we'd rather show the user nothing than spam them with
/// low-signal nudges.
struct SmartCyclePlannerCard: View {
    let suggestions: [SmartCyclePlanner.Suggestion]

    private var displayed: [SmartCyclePlanner.Suggestion] {
        // Hide low-confidence noise; cap at three so the card stays
        // a glance, not a list.
        Array(
            suggestions
                .filter { $0.confidence >= .medium }
                .prefix(3)
        )
    }

    var body: some View {
        if displayed.isEmpty {
            EmptyView()
        } else {
            GlassCard(tinted: true) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    header
                    ForEach(displayed) { suggestion in
                        row(for: suggestion)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppColor.accentLight)
            Text("SMART PLANNER")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(AppColor.accentLight)
            Spacer(minLength: 0)
        }
    }

    private func row(for suggestion: SmartCyclePlanner.Suggestion) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: glyph(for: suggestion.kind))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: 28, height: 28)
                .background {
                    Circle().fill(AppColor.accentPrimary.opacity(0.15))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                Text(suggestion.rationale)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private func glyph(for kind: SmartCyclePlanner.Kind) -> String {
        switch kind {
        case .shortenNextCycle:  "scissors"
        case .shiftDoseTime:     "clock.arrow.circlepath"
        case .cycleWrappingUp:   "flag.checkered"
        case .offCycleReady:     "arrow.clockwise.circle.fill"
        case .considerPausing:   "pause.circle.fill"
        }
    }
}
