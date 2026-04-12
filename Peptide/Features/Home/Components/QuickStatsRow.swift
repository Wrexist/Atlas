import SwiftUI

struct QuickStatsRow: View {
    let activeProtocols: Int
    let daysLogged: Int
    let compliance: Int
    let nextDose: ProtocolEntry?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                GlassStatPill(
                    value: "\(activeProtocols)",
                    label: "Active",
                    icon: "list.clipboard.fill"
                )

                GlassStatPill(
                    value: "\(daysLogged)",
                    label: "Days Logged",
                    icon: "calendar"
                )

                GlassStatPill(
                    value: "\(compliance)%",
                    label: "Compliance",
                    icon: "chart.bar.fill"
                )

                GlassStatPill(
                    value: nextDose?.date.formatted(.dateTime.hour().minute()) ?? "--",
                    label: "Next Dose",
                    icon: "clock.fill"
                )
            }
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        QuickStatsRow(activeProtocols: 2, daysLogged: 45, compliance: 82, nextDose: nil)
            .padding(.leading, Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
