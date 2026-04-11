import SwiftUI

enum AppAnimation {
    static let springSnappy = Animation.spring(response: 0.35, dampingFraction: 0.75)
    static let springBouncy = Animation.spring(response: 0.5, dampingFraction: 0.7)
    static let springSmooth = Animation.spring(response: 0.6, dampingFraction: 0.85)
    static let springGentle = Animation.spring(response: 0.8, dampingFraction: 0.9)

    static let fadeIn = Animation.easeOut(duration: 0.25)
    static let fadeInSlow = Animation.easeOut(duration: 0.4)

    static let staggerDelay: Double = 0.05
    static let sectionDelay: Double = 0.15

    static func staggered(index: Int) -> Animation {
        springBouncy.delay(Double(index) * staggerDelay)
    }

    static func sectionStaggered(index: Int) -> Animation {
        springSmooth.delay(Double(index) * sectionDelay)
    }
}
