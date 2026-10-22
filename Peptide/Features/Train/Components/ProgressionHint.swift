import SwiftUI

/// The load to beat today and why, above an exercise's sets. "Use" fills
/// the unchecked sets when they don't already carry the suggestion: always
/// the case with auto-progression off, or after the user edited them.
struct ProgressionHint: View {
    let suggestion: ProgressionEngine.Suggestion
    let unit: MeasurementUnit
    let canApply: Bool
    let onApply: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: symbolName)
                .foregroundStyle(AppColor.accentPrimary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Today: \(target)")
                    .font(AppFont.callout.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text(reason)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Spacing.xs)
            if canApply {
                Button {
                    Haptics.selection()
                    onApply()
                } label: {
                    Text("Use").font(AppFont.callout.weight(.semibold)).minimumHitArea()
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.accentPrimary)
                .accessibilityHint(Text("Fills the unchecked sets with \(target)"))
            }
        }
    }

    private var target: String {
        suggestion.weightKg > 0
            ? "\(unit.weightValue(suggestion.weightKg, fractionDigits: 0...2)) \(unit.weightSuffix) × \(suggestion.reps)"
            : String(AttributedString(localized: "^[\(suggestion.reps) rep](inflect: true)").characters)
    }

    private var symbolName: String {
        switch suggestion.reason {
        case .addWeight: return "arrow.up.circle.fill"
        case .addRep, .reachRange: return "plus.circle.fill"
        case .repeatLoad: return "equal.circle.fill"
        }
    }

    private var reason: String {
        switch suggestion.reason {
        case .addWeight: return String(localized: "Every set hit its reps last time, so add weight.")
        case .addRep: return String(localized: "Same weight, one more rep than last time.")
        case .reachRange: return String(localized: "Same weight, aim for the bottom of the rep range.")
        case .repeatLoad: return String(localized: "Repeat last time's weight until every set hits its reps.")
        }
    }
}
