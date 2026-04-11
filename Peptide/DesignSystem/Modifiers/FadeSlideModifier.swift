import SwiftUI

struct FadeSlideModifier: ViewModifier {
    var delay: Double = 0
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .onAppear {
                withAnimation(AppAnimation.springSmooth.delay(delay)) {
                    appeared = true
                }
            }
    }
}

extension View {
    func fadeSlide(delay: Double = 0) -> some View {
        modifier(FadeSlideModifier(delay: delay))
    }
}
