import SwiftUI

// Backward-compatible wrapper for the iOS 26 glassEffect modifier.
// On iOS 17–25 views render with their existing solid/translucent background;
// on iOS 26+ the system Liquid Glass material is composited on top.

enum GlassPreset {
    case circle
    case capsule
    case rect(cornerRadius: CGFloat)
}

extension View {
    @ViewBuilder
    func liquidGlass(_ preset: GlassPreset) -> some View {
        if #available(iOS 26.0, *) {
            switch preset {
            case .circle:
                self.glassEffect(in: .circle)
            case .capsule:
                self.glassEffect(in: .capsule)
            case .rect(let r):
                self.glassEffect(in: .rect(cornerRadius: r))
            }
        } else {
            self
        }
    }
}
