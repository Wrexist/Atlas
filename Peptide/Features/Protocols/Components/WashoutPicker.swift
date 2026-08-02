import SwiftUI

/// Toggle-then-stepper for the optional wash-out duration.
///
/// Most protocols don't repeat — the user takes a single run and
/// moves on. For the subset that *do* run cyclically (BPC-157,
/// TB-500, retatrutide cycles), the wash-out window matters a lot
/// for safety + receptor sensitivity reasons. This control keeps
/// the typical case (no wash-out) frictionless while exposing the
/// option clearly when the user reaches for it.
///
/// Default value when the user flips the toggle on: 4 weeks. Picked
/// as a sane starting point for the most common cycling peptides;
/// users can stepper up or down from there.
struct WashoutPicker: View {
    @Binding var washoutWeeks: Int

    private static let defaultWhenEnabled: Int = 4

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { washoutWeeks > 0 },
            set: { newValue in
                washoutWeeks = newValue ? Self.defaultWhenEnabled : 0
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Toggle(isOn: isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cycle with wash-out")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Alternate on/off periods to preserve receptor sensitivity.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(AppColor.accentPrimary)

            if isEnabled.wrappedValue {
                stepperRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: isEnabled.wrappedValue)
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
    }

    private var stepperRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Wash-out length")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(footerCopy)
                    .font(AppFont.scaled(11))
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
            }
            Spacer()
            Stepper(
                value: $washoutWeeks,
                in: 1...12,
                step: 1
            ) {
                HStack(spacing: 4) {
                    Text("\(washoutWeeks)")
                        .font(AppFont.scaled(20, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                        .contentTransition(.numericText())
                    Text(washoutWeeks == 1 ? "week" : "weeks")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .tint(AppColor.accentPrimary)
        }
    }

    private var footerCopy: LocalizedStringResource {
        // "8 weeks on, 4 weeks off" reads as the canonical cycle
        // description in this community. Use the wash-out value to
        // build the matching phrase so the user sees the full
        // cycle shape they're building.
        LocalizedStringResource(
            "Cycle repeats — \(washoutWeeks)w off between runs.",
            comment: "Footer beneath the wash-out stepper, showing the cycle shape."
        )
    }
}
