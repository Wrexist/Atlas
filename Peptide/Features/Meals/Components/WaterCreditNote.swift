import SwiftUI

/// One line under a drink's portion picker saying how much of it also
/// counts toward the day's water, so the extra log is never a surprise.
/// Draws nothing for food or a drink with calories.
struct WaterCreditNote: View {
    let millilitres: Double?
    /// The unit the water ring speaks, so an imperial user reads ounces.
    let unit: MeasurementUnit

    var body: some View {
        if let millilitres {
            let amount = unit.volumeValue(LifestyleDataLogic.fluidOunces(millilitres: millilitres))
            Label {
                Group {
                    if unit == .metric {
                        Text("Also counts as \(amount) mL water")
                    } else {
                        Text("Also counts as \(amount) oz water")
                    }
                }
                .contentTransition(.numericText(value: Double(amount)))
            } icon: {
                Image(systemName: "drop.fill")
                    .foregroundStyle(AppColor.accentLight)
            }
            .font(AppFont.caption2)
            .foregroundStyle(AppColor.textSecondary)
            .monospacedDigit()
            .accessibilityElement(children: .combine)
        }
    }
}
