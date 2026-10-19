import SwiftUI

struct CycleProgressBar: View {
    let protocol_: PeptideProtocol

    var body: some View {
        VStack(spacing: Spacing.xs) {
            GlassProgressBar(progress: protocol_.cycleProgress)

            HStack {
                Text(protocol_.startDate.formatted(.dateTime.month(.abbreviated).day()))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)

                Spacer()

                Text("\(Int(protocol_.cycleProgress * 100))%")
                    .font(AppFont.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(AppColor.accentLight)

                Spacer()

                Text(protocol_.endDate.formatted(.dateTime.month(.abbreviated).day()))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
        .appAnimation(AppAnimation.springSnappy, value: protocol_.cycleProgress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cycle progress")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let start = protocol_.startDate.formatted(.dateTime.month(.wide).day())
        let end = protocol_.endDate.formatted(.dateTime.month(.wide).day())
        return "\(Int(protocol_.cycleProgress * 100)) percent, \(start) to \(end)"
    }
}
