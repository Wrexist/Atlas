import SwiftUI

struct ReadyHero: View {
    let bounceTrigger: Int
    @State private var ringScale: CGFloat = 0.8
    @State private var ringOpacity: Double = 0.6

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .strokeBorder(AppColor.accentPrimary.opacity(0.5), lineWidth: 1)
                    .frame(width: 130, height: 130)
                    .scaleEffect(ringScale + CGFloat(index) * 0.15)
                    .opacity(ringOpacity - Double(index) * 0.15)
            }

            HeroIcon(symbol: "checkmark.circle.fill", size: 100, bounceTrigger: bounceTrigger)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                ringScale = 1.7
                ringOpacity = 0
            }
        }
    }
}
