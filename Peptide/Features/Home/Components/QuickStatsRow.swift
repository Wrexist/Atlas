import SwiftUI

struct QuickStatsRow: View {
    let activeProtocols: Int
    let daysLogged: Int
    let streak: Int

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
                    value: "\(streak)",
                    label: "Day Streak",
                    icon: "flame.fill"
                )

                GlassStatPill(
                    value: "2:00 PM",
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
        QuickStatsRow(activeProtocols: 2, daysLogged: 45, streak: 12)
            .padding(.leading, Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
