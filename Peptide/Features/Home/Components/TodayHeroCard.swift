import SwiftUI

/// Today's lit summary card: one ring for how far the whole day has come,
/// and a bar per health goal (calories, steps, water, habits) beside it. Accent fill
/// with a slow-moving light, a tinted lift, and a few degrees of tilt as
/// the phone moves or the card scrolls away, so the first thing on Today
/// is an object with weight rather than another flat list.
struct TodayHeroCard: View {
    struct Part: Identifiable, Equatable {
        enum Kind: String { case calories, steps, water, habits }
        let kind: Kind
        /// 0…1 toward the day's goal.
        let fraction: Double
        /// What the bar's trailing figure reads, already formatted.
        let value: String
        var id: Kind { kind }

        init(kind: Kind, fraction: Double, value: String) {
            self.kind = kind
            self.fraction = min(max(fraction, 0), 1)
            self.value = value
        }

        /// A goal read as a share of its target.
        init(kind: Kind, amount: Double, goal: Double) {
            self.init(
                kind: kind,
                fraction: goal > 0 ? amount / goal : 0,
                value: (goal > 0 ? amount / goal : 0).formatted(.percent.precision(.fractionLength(0)))
            )
        }

        /// A count of things to tick off, read as a share like the rest
        /// so every bar's figure scans the same way.
        init(kind: Kind, done: Int, total: Int) {
            self.init(kind: kind, amount: Double(done), goal: Double(total))
        }
    }

    let parts: [Part]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var drawn = false
    @State private var isOnScreen = true
    @State private var isShown = false

    /// Every goal weighs the same, so a full water bottle counts as
    /// much as a full plate.
    private var progress: Double {
        parts.isEmpty ? 0 : parts.reduce(0) { $0 + $1.fraction } / Double(parts.count)
    }

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
            .heroTilt(isLive: isLive)
            .onScrollVisibilityChange { isOnScreen = $0 }
            .onAppear {
                isShown = true
                AppAnimation.with(AppAnimation.draw) { drawn = true }
            }
            .onDisappear { isShown = false }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Daily goals"))
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
        Text("Daily goals")
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
        let lines = parts.map { "\(String(localized: $0.title)) \($0.value)" }
        return ([percent] + lines).joined(separator: ", ")
    }
}

private extension TodayHeroCard.Part {
    var title: LocalizedStringResource {
        switch kind {
        case .calories: "Calories"
        case .steps: "Steps"
        case .water: "Water"
        case .habits: "Habits"
        }
    }

    var symbol: String {
        switch kind {
        case .calories: "flame"
        case .steps: "figure.walk"
        case .water: "drop"
        case .habits: "checkmark.seal"
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
        let deep = AppColor.accentFill.mix(with: AppColor.accentDeep, by: light ? 0.2 : 1)
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

// MARK: - Ring

/// The day's ring, drawn on the accent: a recessed track and a bright
/// arc that casts a small shadow onto it.
private struct TodayHeroRing: View {
    let progress: Double

    private static let stroke: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColor.onAccent.opacity(0.25), lineWidth: Self.stroke)
            Circle()
                .trim(from: 0, to: max(progress, 0.001))
                .stroke(AppColor.onAccent, style: StrokeStyle(lineWidth: Self.stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .appShadow(AppShadow.ringLap)
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
                Text(verbatim: part.value)
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
        .appAnimation(AppAnimation.springSmooth, value: part.fraction)
    }
}

// MARK: - Backdrop

/// Today's page: the shared backdrop plus, in dark mode, a pool of
/// accent light behind the hero that dims as the page scrolls. Light
/// mode keeps the plain warm page; green over cream turned it grey.
struct TodayBackdrop: View {
    /// 0 at rest, 1 once the header has scrolled away. A binding, so a
    /// scroll frame re-renders the backdrop and not the whole page.
    @Binding var fade: Double

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
        .init(kind: .calories, amount: 1620, goal: 2400),
        .init(kind: .steps, amount: 6210, goal: 8000),
        .init(kind: .water, amount: 48, goal: 100),
        .init(kind: .habits, done: 3, total: 5),
    ])
    .padding()
    .pageBackground()
}
