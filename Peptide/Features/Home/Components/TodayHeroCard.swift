import SwiftUI

/// Today's lit summary card: one ring for how much of the day is done,
/// and a bar per source (doses, checklist, habits) beside it. Accent fill
/// with a slow-moving light, a tinted lift, and a few degrees of tilt as
/// the phone moves or the card scrolls away, so the first thing on Today
/// is an object with weight rather than another flat list.
struct TodayHeroCard: View {
    struct Part: Identifiable, Equatable {
        enum Kind: String { case doses, checklist, habits }
        let kind: Kind
        let done: Int
        let total: Int
        var id: Kind { kind }
        var fraction: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }
    }

    let parts: [Part]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var drawn = false
    @State private var isOnScreen = true
    @State private var isShown = false

    private var done: Int { parts.reduce(0) { $0 + min($1.done, $1.total) } }
    private var total: Int { parts.reduce(0) { $0 + $1.total } }
    private var progress: Double { total > 0 ? Double(done) / Double(total) : 0 }

    /// Ambient light and tilt run only while the card is on screen, and
    /// never for reduce motion or screenshot captures, which need still
    /// frames.
    private var isLive: Bool {
        isOnScreen && isShown && !reduceMotion && !ScreenshotMode.shared.isEnabled
    }

    var body: some View {
        content
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { TodayHeroSurface(isLive: isLive) }
            .modifier(TodayHeroTilt(isLive: isLive))
            .onScrollVisibilityChange { isOnScreen = $0 }
            .onAppear {
                isShown = true
                AppAnimation.with(AppAnimation.draw) { drawn = true }
            }
            .onDisappear { isShown = false }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Your day"))
            .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var content: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                heading
                ring
                bars
            }
        } else {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                heading
                HStack(alignment: .center, spacing: Spacing.xl) {
                    ring
                    bars
                }
            }
        }
    }

    private var heading: some View {
        Text("Your day")
            .font(AppFont.eyebrow)
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(AppColor.onAccent.opacity(0.78))
    }

    private var ring: some View {
        TodayHeroRing(progress: drawn ? progress : 0)
            .frame(width: 96, height: 96)
    }

    private var bars: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(parts) { part in
                TodayHeroBar(part: part, drawn: drawn)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var accessibilityValue: String {
        let percent = progress.formatted(.percent.precision(.fractionLength(0)))
        let lines = parts.map { "\(String(localized: $0.title)) \($0.done)/\($0.total)" }
        return ([percent] + lines).joined(separator: ", ")
    }
}

private extension TodayHeroCard.Part {
    var title: LocalizedStringResource {
        switch kind {
        case .doses: "Doses"
        case .checklist: "Checklist"
        case .habits: "Habits"
        }
    }

    var symbol: String {
        switch kind {
        case .doses: "syringe"
        case .checklist: "checklist"
        case .habits: "flame"
        }
    }
}

// MARK: - Surface

/// The card's body: one key light from the top left falling off to a
/// shaded bottom right, drifting slowly, a gloss over the top half, a lit rim, and
/// a tinted drop under it all.
private struct TodayHeroSurface: View {
    let isLive: Bool

    @Environment(\.colorScheme) private var colorScheme

    /// Seconds for one full drift of the light.
    private static let driftPeriod: TimeInterval = 18
    private static let radius: CGFloat = Spacing.sheetCornerRadius

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !isLive)) { timeline in
            let phase = isLive
                ? timeline.date.timeIntervalSinceReferenceDate / Self.driftPeriod * 2 * .pi
                : 0
            mesh(phase: phase)
        }
        .clipShape(shape)
        .overlay {
            shape.fill(
                LinearGradient(
                    colors: [AppColor.onAccent.opacity(0.14), AppColor.onAccent.opacity(0)],
                    startPoint: .top,
                    endPoint: .center
                )
            )
        }
        .overlay {
            shape.strokeBorder(
                LinearGradient(
                    colors: [AppColor.onAccent.opacity(0.36), AppColor.onAccent.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        }
        .appShadow(AppShadow.paperContact)
        .appShadow(AppShadow.heroLift)
    }

    /// Interior points orbit a few percent around their rest spots; the
    /// corners stay pinned so the card's edge never shows a seam.
    private func mesh(phase: Double) -> MeshGradient {
        let drift = Float(0.06)
        let s = Float(sin(phase))
        let c = Float(cos(phase * 0.8))
        // Light mode keeps the falloff shallow: a near-black corner on a
        // cream page outweighs everything else on screen.
        let light = colorScheme == .light
        let deep = AppColor.accentFill.mix(with: AppColor.accentDeep, by: light ? 0.35 : 1)
        let fill = AppColor.accentFill
        let sheen = AppColor.accentFill.mix(with: AppColor.accentSheen, by: light ? 0.6 : 0.8)
        return MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5 + drift * s, 0], [1, 0],
                [0, 0.5 + drift * c], [0.5 + drift * c, 0.5 + drift * s], [1, 0.5 - drift * s],
                [0, 1], [0.5 - drift * c, 1], [1, 1],
            ],
            colors: [
                sheen, sheen, fill,
                sheen, fill, fill,
                fill, fill, deep,
            ]
        )
    }
}

// MARK: - Tilt

/// Two sources of depth: the phone's own tilt nudges the card a few
/// degrees toward the hand, and scrolling it under the bar tips it back
/// like a lid closing.
private struct TodayHeroTilt: ViewModifier {
    let isLive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt = DeviceTilt.shared
    @State private var leased = false

    /// Degrees of card swing per radian of phone tilt.
    private static let gain = 22.0

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(isLive ? tilt.pitch * Self.gain : 0),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.6
            )
            .rotation3DEffect(
                .degrees(isLive ? -tilt.roll * Self.gain : 0),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.6
            )
            .appAnimation(AppAnimation.springSnappy, value: tilt.pitch)
            .appAnimation(AppAnimation.springSnappy, value: tilt.roll)
            .visualEffect { [reduceMotion] effect, proxy in
                let lift = reduceMotion ? 0 : Self.scrollLift(minY: proxy.frame(in: .scrollView).minY)
                return effect
                    .rotation3DEffect(.degrees(lift * 18), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
                    .scaleEffect(1 - lift * 0.06, anchor: .bottom)
                    .opacity(1 - lift * 0.5)
            }
            .onChange(of: isLive, initial: true) { _, live in lease(live) }
            .onDisappear { lease(false) }
    }

    /// 0 while the card sits below the bar, rising to 1 over the next
    /// 160pt as it scrolls up beneath it.
    private nonisolated static func scrollLift(minY: CGFloat) -> Double {
        min(max((96 - minY) / 160, 0), 1)
    }

    private func lease(_ live: Bool) {
        guard live != leased else { return }
        leased = live
        live ? tilt.start() : tilt.stop()
    }
}

// MARK: - Ring

/// The day's ring, drawn on the accent: a recessed track, a bright arc,
/// and a raised knob at its head.
private struct TodayHeroRing: View {
    let progress: Double

    private static let stroke: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColor.onAccent.opacity(0.25), lineWidth: Self.stroke)
            Circle()
                .trim(from: 0, to: max(progress, 0.001))
                .stroke(
                    AngularGradient(
                        colors: [AppColor.onAccent.opacity(0.55), AppColor.onAccent],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(progress, 0.001))
                    ),
                    style: StrokeStyle(lineWidth: Self.stroke, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .appShadow(AppShadow.ringLap)
            knob
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(AppFont.scaled(24, weight: .semibold, relativeTo: .title3))
                .monospacedDigit()
                .foregroundStyle(AppColor.onAccent)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .padding(.horizontal, Self.stroke + Spacing.xs)
        }
        .appAnimation(AppAnimation.springSmooth, value: progress)
    }

    /// The arc's head as a small raised bead, so the ring reads as a
    /// physical track rather than a line. Hidden at zero, where there's
    /// no arc to lead.
    private var knob: some View {
        GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height) / 2
            let angle = Angle.degrees(360 * progress - 90)
            Circle()
                .fill(AppColor.onAccent)
                .frame(width: Self.stroke - 2, height: Self.stroke - 2)
                .appShadow(AppShadow.tileDrop)
                .position(
                    x: r + cos(angle.radians) * r,
                    y: r + sin(angle.radians) * r
                )
                .opacity(progress > 0.02 ? 1 : 0)
        }
    }
}

// MARK: - Bar

private struct TodayHeroBar: View {
    let part: TodayHeroCard.Part
    let drawn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: part.symbol)
                    .font(AppFont.chipText)
                    .accessibilityHidden(true)
                Text(part.title)
                    .font(AppFont.chipText)
                Spacer(minLength: Spacing.xs)
                Text(verbatim: "\(part.done)/\(part.total)")
                    .font(AppFont.chipText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(AppColor.onAccent)
            Capsule()
                .fill(AppColor.onAccent.opacity(0.25))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(AppColor.onAccent)
                            .frame(width: max(6, geo.size.width * (drawn ? part.fraction : 0)))
                            .opacity(part.fraction > 0 && drawn ? 1 : 0)
                    }
                }
        }
        .appAnimation(AppAnimation.springSmooth, value: part.done)
    }
}

// MARK: - Backdrop

/// Today's page: the shared backdrop plus, in dark mode, a pool of
/// accent light behind the hero that dims as the page scrolls. Light
/// mode keeps the plain warm page; green over cream turned it grey.
struct TodayBackdrop: View {
    /// 0 at rest, 1 once the header has scrolled away.
    let fade: Double

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        PageBackdrop()
            .overlay {
                RadialGradient(
                    colors: [AppColor.accentPrimary.opacity(colorScheme == .dark ? 0.13 : 0), AppColor.accentPrimary.opacity(0)],
                    center: UnitPoint(x: 0.3, y: 0.08),
                    startRadius: 0,
                    endRadius: 300
                )
                .opacity(1 - fade * 0.7)
            }
    }
}

#Preview {
    TodayHeroCard(parts: [
        .init(kind: .doses, done: 3, total: 8),
        .init(kind: .checklist, done: 1, total: 4),
        .init(kind: .habits, done: 2, total: 3),
    ])
    .padding()
    .pageBackground()
}
