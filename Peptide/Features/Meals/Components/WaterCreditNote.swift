import SwiftUI

/// One line under a drink's portion picker saying how much of it also
/// counts toward the day's water, so the extra log is never a surprise.
/// Draws nothing for food or a drink with calories.
struct WaterCreditNote: View {
    let millilitres: Double?

    var body: some View {
        if let millilitres {
            Label {
                Text("Also counts as \(Int(millilitres.rounded())) ml water")
                    .contentTransition(.numericText(value: millilitres))
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
