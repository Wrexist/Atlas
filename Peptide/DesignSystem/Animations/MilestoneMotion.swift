import SwiftUI

enum MilestoneMotionStyle {
    case settle
    case flicker
    case shine
}

/// One short performance, then a still. The owner supplies a semantic trigger;
/// mounting an adjacent onboarding page must not consume its arrival animation.
private struct MilestoneMotion: ViewModifier {
    let trigger: Int
    let isActive: Bool
    let playsOnArrival: Bool
    let style: MilestoneMotionStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var lastPlayedTrigger: Int?
    @State private var animationTrigger = 0

    private struct Request: Equatable {
        let trigger: Int
        let enabled: Bool
    }

    private struct Pose {
        var scale: CGFloat = 1
        var lift: CGFloat = 0
        var tilt: Double = 0
        var sheen: CGFloat = -1
    }

    private var enabled: Bool {
        isActive && isVisible && !reduceMotion && scenePhase == .active
    }

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: Pose(), trigger: animationTrigger) { view, pose in
                view
                    .overlay {
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(LinearGradient(
                                    colors: [.clear, AppColor.onAccent.opacity(0.38), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                                .frame(width: geometry.size.width * 0.3)
                                .rotationEffect(.degrees(18))
                                .offset(x: geometry.size.width * pose.sheen)
                        }
                        .mask(content)
                        .opacity(enabled ? 1 : 0)
                        .allowsHitTesting(false)
                    }
                    .scaleEffect(
                        x: enabled && style != .shine ? (style == .flicker ? 2 - pose.scale : pose.scale) : 1,
                        y: enabled && style != .shine ? pose.scale : 1,
                        anchor: style == .flicker ? .bottom : .center
                    )
                    .rotation3DEffect(.degrees(enabled && style == .settle ? pose.tilt : 0), axis: (x: 0, y: 1, z: 0))
                    .offset(y: enabled && style == .settle ? pose.lift : 0)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(0.94, duration: 0.12)
                    CubicKeyframe(1.04, duration: 0.26)
                    CubicKeyframe(1, duration: 0.42)
                }
                KeyframeTrack(\.lift) {
                    CubicKeyframe(-3, duration: 0.3)
                    CubicKeyframe(0, duration: 0.5)
                }
                KeyframeTrack(\.tilt) {
                    CubicKeyframe(-8, duration: 0.18)
                    CubicKeyframe(3, duration: 0.28)
                    CubicKeyframe(0, duration: 0.34)
                }
                KeyframeTrack(\.sheen) {
                    MoveKeyframe(-1)
                    LinearKeyframe(-1, duration: 0.18)
                    CubicKeyframe(1.4, duration: 0.62)
                }
            }
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .onScrollVisibilityChange(threshold: 0.2) { isVisible = $0 }
            .task(id: Request(trigger: trigger, enabled: enabled)) {
                guard enabled, lastPlayedTrigger != trigger else { return }
                if lastPlayedTrigger == nil && !playsOnArrival {
                    lastPlayedTrigger = trigger
                    return
                }
                // Let the animator mount before delivering its first trigger.
                await Task.yield()
                guard !Task.isCancelled else { return }
                lastPlayedTrigger = trigger
                animationTrigger &+= 1
            }
    }
}

extension View {
    func milestoneMotion(
        trigger: Int = 0,
        isActive: Bool = true,
        playsOnArrival: Bool = true,
        style: MilestoneMotionStyle = .settle
    ) -> some View {
        modifier(MilestoneMotion(trigger: trigger, isActive: isActive, playsOnArrival: playsOnArrival, style: style))
    }
}
