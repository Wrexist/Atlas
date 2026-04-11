import SwiftUI

struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .scaleEffect(appeared ? 1 : 0.95)
            .onAppear {
                withAnimation(AppAnimation.staggered(index: index)) {
                    appeared = true
                }
            }
    }
}

struct SectionAppear: ViewModifier {
    let index: Int
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 30)
            .onAppear {
                withAnimation(AppAnimation.sectionStaggered(index: index)) {
                    appeared = true
                }
            }
    }
}

extension View {
    func staggeredAppear(index: Int) -> some View {
        modifier(StaggeredAppear(index: index))
    }

    func sectionAppear(index: Int) -> some View {
        modifier(SectionAppear(index: index))
    }
}
