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
                    .foregroundStyle(AppColor.accentLight)

                Spacer()

                Text(protocol_.endDate.formatted(.dateTime.month(.abbreviated).day()))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
    }
}
