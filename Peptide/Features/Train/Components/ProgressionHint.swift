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
            : String(localized: "\(suggestion.reps) reps")
    }

    private var symbolName: String {
        if suggestion.adjustment != nil { return "arrow.down.circle.fill" }
        switch suggestion.reason {
        case .addWeight: return "arrow.up.circle.fill"
        case .addRep, .reachRange: return "plus.circle.fill"
        case .repeatLoad: return "equal.circle.fill"
        }
    }

    private var reason: String {
        switch suggestion.adjustment {
        case .lowRecovery: return String(localized: "Lighter today to match your recovery.")
        case .deload: return String(localized: "Deload week: lighter, with about a third fewer reps.")
        case nil: break
        }
        switch suggestion.reason {
        case .addWeight: return String(localized: "Every set hit its reps last time, so add weight.")
        case .addRep: return String(localized: "Same weight, one more rep than last time.")
        case .reachRange: return String(localized: "Same weight, aim for the bottom of the rep range.")
        case .repeatLoad: return String(localized: "Repeat last time's weight until every set hits its reps.")
        }
    }
}
