import SwiftUI

/// Bevel-style three-ring hero at the top of Today.
/// Adherence (taken doses) / Recovery (HRV + sleep + RHR composite)
/// / Sleep (last night's hours vs target). Each ring tells a
/// distinct part of "should I push or recover today?" so the user
/// gets the same one-glance answer Bevel / Whoop give for training.
/// The first ring is workouts this week for users without a
/// protocol (see `HeroLeadingMetric`).
///
/// The trio drives off `HeroMetricSnapshot` which is built once on
/// view appear and refreshed when scene phase returns to .active.
/// Async HealthKit reads happen inside the snapshot builder; the
/// view never blocks waiting for them — a ring without data is left
/// out rather than drawn empty, and what's missing is named once in a
/// one-line footer. With no ring to show, that line is the whole card.
struct HeroMetricTrio: View {
    let snapshot: HeroMetricSnapshot
    var onTapRing: ((HeroMetricKind) -> Void)?
    /// Tap handler for the "Connect Apple Health" footer. The footer
    /// used to be display-only — it named the fix (connect Health)
    /// and offered no way to do it (audit Accessibility/empty-state
    /// finding). Nil keeps the footer as a plain label.
    var onConnectHealth: (() -> Void)?
    /// What the first ring measures. Adherence only means something to
    /// a user running a protocol; everyone else gets this week's
    /// workouts against their training-days target.
    var leading: HeroLeadingMetric = .adherence
    var onTapWorkouts: (() -> Void)?
    /// True until the first HealthKit snapshot lands. The rings render
    /// as a shimmering placeholder instead of flashing "—" first.
    var isLoading = false

    /// Width of the ring row, measured so the rings shrink to fit on
    /// small phones instead of clipping. Zero until first layout.
    @State private var rowWidth: CGFloat = 0

    private static let maxRingDiameter: CGFloat = 96
    private static let strokeRatio: CGFloat = 10 / 96

    private var ringDiameter: CGFloat {
        guard rowWidth > 0 else { return Self.maxRingDiameter }
        return min(Self.maxRingDiameter, (rowWidth - 2 * Spacing.sm) / 3)
    }

    private var ringStrokeWidth: CGFloat {
        ringDiameter * Self.strokeRatio
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            if showsRingRow {
                ringRowContainer
            }

            if !isLoading {
                if snapshot.needsHealthConnection {
                    healthConnectionFooter
                } else if snapshot.awaitsHealthData {
                    footerContent(Self.awaitingDataMessage, chevron: false)
                        .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(Spacing.cardPadding)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today's metrics")
    }

    private var shownRings: [HeroMetricKind] {
        Self.shownRings(snapshot: snapshot, leading: leading, isLoading: isLoading)
    }

    private var showsRingRow: Bool {
        Self.showsRingRow(snapshot: snapshot, leading: leading, isLoading: isLoading)
    }

    /// The rings that have data. While loading every ring shows, as a
    /// placeholder, so the card doesn't jump once values land.
    static func shownRings(snapshot: HeroMetricSnapshot, leading: HeroLeadingMetric, isLoading: Bool) -> [HeroMetricKind] {
        let kinds: [HeroMetricKind] = leading == .adherence
            ? [.adherence, .recovery, .sleep]
            : [.recovery, .sleep]
        return isLoading ? kinds : kinds.filter { snapshot.value(for: $0).isAvailable }
    }

    /// False when the card is only a footer line, which Today then shows
    /// without its "At a glance" header.
    static func showsRingRow(snapshot: HeroMetricSnapshot, leading: HeroLeadingMetric, isLoading: Bool) -> Bool {
        leading != .adherence || !shownRings(snapshot: snapshot, leading: leading, isLoading: isLoading).isEmpty
    }

    private var ringRowContainer: some View {
        Group {
            if isLoading {
                ringRow
                    .redacted(reason: .placeholder)
                    .shimmer()
                    .allowsHitTesting(false)
                    .accessibilityLabel("Loading today's metrics")
            } else {
                ringRow
            }
        }
        // minWidth 0 makes the frame report the proposed width even
        // while the rings are still at full size, so the measurement
        // below is the space available rather than the rings' width.
        .frame(minWidth: 0, maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
    }

    private var ringRow: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            if case .workouts(let done, let target) = leading {
                workoutsTile(done: done, target: target)
            }
            ForEach(Array(shownRings.enumerated()), id: \.element) { offset, kind in
                ringTile(kind, value: snapshot.value(for: kind), order: offset + leadingRingCount)
            }
        }
    }

    // MARK: - Ring tile

    /// The workouts ring fills first when it leads the row.
    private var leadingRingCount: Int {
        if case .workouts = leading { 1 } else { 0 }
    }

    /// Rings fill left to right, one beat apart.
    private static func appearDelay(order: Int) -> Double {
        Double(order) * AppAnimation.sectionDelay * 2
    }

    /// How far a ring drifts over the card as the phone tips.
    private static let parallaxDepth: CGFloat = 3

    @ViewBuilder
    private func ringTile(_ kind: HeroMetricKind, value: HeroMetricValue, order: Int) -> some View {
        Button {
            onTapRing?(kind)
        } label: {
            VStack(spacing: Spacing.xs) {
                MetricRing(
                    progress: value.progress,
                    diameter: ringDiameter,
                    strokeWidth: ringStrokeWidth,
                    gradient: kind.gradient(active: value.isAvailable),
                    // Only Adherence celebrates at 100% — it's the
                    // ring the user actively drives by logging
                    // doses. Recovery + Sleep crossing 100 would be
                    // a false positive (great recovery is the
                    // ceiling, not a finished task).
                    appearAnimated: true,
                    celebrateAtCompletion: kind == .adherence,
                    raised: true,
                    appearDelay: Self.appearDelay(order: order)
                ) {
                    ringCenter(kind: kind, value: value)
                }
                .tiltParallax(depth: Self.parallaxDepth)

                Text(kind.label)
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.96))
        .accessibilityLabel(value.accessibilityLabel(for: kind))
    }

    private func workoutsTile(done: Int, target: Int) -> some View {
        let progress = target > 0 ? min(1, Double(done) / Double(target)) : 0
        return Button {
            onTapWorkouts?()
        } label: {
            VStack(spacing: Spacing.xs) {
                MetricRing(
                    progress: progress,
                    diameter: ringDiameter,
                    strokeWidth: ringStrokeWidth,
                    gradient: [AppColor.accentLight, AppColor.accentPrimary],
                    appearAnimated: true,
                    celebrateAtCompletion: true,
                    raised: true
                ) {
                    Text("\(done)/\(target)")
                        .font(AppFont.scaled(20, weight: .medium))
                        .foregroundStyle(AppColor.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                }
                .tiltParallax(depth: Self.parallaxDepth)

                Text("Training days")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.96))
        .accessibilityLabel("Training days this week, \(done) of \(target)")
        .accessibilityHint("Opens Train")
    }

    @ViewBuilder
    private func ringCenter(kind: HeroMetricKind, value: HeroMetricValue) -> some View {
        if value.isAvailable {
            Text("\(value.displayPercent)%")
                .font(AppFont.scaled(20, weight: .medium))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
        } else {
            Text("—")
                .font(AppFont.scaled(20, weight: .bold))
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var healthConnectionFooter: some View {
        if let onConnectHealth {
            Button(action: onConnectHealth) {
                footerContent(Self.connectHealthMessage, chevron: true)
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.96))
            .minimumHitArea()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Connect Apple Health for Recovery and Sleep scores")
            .accessibilityHint("Asks for Apple Health access")
        } else {
            footerContent(Self.connectHealthMessage, chevron: false)
        }
    }

    private static var connectHealthMessage: LocalizedStringKey {
        "Connect Apple Health for Recovery and Sleep scores"
    }
    private static var awaitingDataMessage: LocalizedStringKey {
        "Not enough recent Health data — wear your Apple Watch overnight to build a baseline"
    }

    private func footerContent(_ message: LocalizedStringKey, chevron: Bool) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "heart.text.square.fill")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
            Text(message)
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
        .padding(.horizontal, Spacing.xs)
        .contentShape(Rectangle())
    }
}

// MARK: - Snapshot types

enum HeroLeadingMetric: Equatable {
    case adherence
    case workouts(done: Int, target: Int)
}

enum HeroMetricKind: Hashable, CaseIterable {
    case adherence, recovery, sleep

    var label: LocalizedStringKey {
        switch self {
        case .adherence: "Adherence"
        case .recovery:  "Recovery"
        case .sleep:     "Sleep"
        }
    }

    /// Glyph shown inside the ring on the detail sheet, above the
    /// number. The ring alone says "a percentage of something"; this
    /// says which something, before the eye reaches the title.
    var icon: String {
        switch self {
        case .adherence: "checkmark.shield.fill"
        case .recovery:  "bolt.heart.fill"
        case .sleep:     "moon.fill"
        }
    }

    /// Glyph on the "why it matters" medallion. Deliberately not `icon`
    /// — repeating the same symbol twelve points below itself reads as a
    /// rendering mistake.
    var explainerIcon: String {
        switch self {
        case .adherence: "calendar.badge.checkmark"
        case .recovery:  "bolt.fill"
        case .sleep:     "bed.double.fill"
        }
    }

    /// Gradient stops drawn into the ring's angular gradient. The
    /// dimmed variant kicks in when the metric has no data so the
    /// "—" centre reads as inactive without being invisible.
    func gradient(active: Bool) -> [Color] {
        guard active else {
            return [AppColor.textSecondary.opacity(0.45), AppColor.textSecondary.opacity(0.25)]
        }
        switch self {
        case .adherence:
            return [AppColor.accentLight, AppColor.accentPrimary]
        case .recovery:
            return [AppColor.ringRecoveryStart, AppColor.ringRecoveryEnd]
        case .sleep:
            return [AppColor.ringSleepStart, AppColor.ringSleepEnd]
        }
    }
}

/// Per-ring value carrier. `progress` (0…1) drives the arc;
/// `displayPercent` is the user-facing integer the centre shows;
/// `isAvailable` is false when the input data is missing so the
/// ring degrades cleanly instead of pegging at 0%.
struct HeroMetricValue: Equatable, Sendable {
    let progress: Double
    let displayPercent: Int
    let isAvailable: Bool

    static let unavailable = HeroMetricValue(progress: 0, displayPercent: 0, isAvailable: false)

    static func percent(_ raw: Double) -> HeroMetricValue {
        let clamped = max(0, min(1, raw))
        return HeroMetricValue(
            progress: clamped,
            displayPercent: Int((clamped * 100).rounded()),
            isAvailable: true
        )
    }

    func accessibilityLabel(for kind: HeroMetricKind) -> String {
        let name: String
        switch kind {
        case .adherence: name = String(localized: "Adherence")
        case .recovery:  name = String(localized: "Recovery")
        case .sleep:     name = String(localized: "Sleep")
        }
        guard isAvailable else {
            return kind == .adherence
                ? String(localized: "\(name), no doses today")
                : String(localized: "\(name), no data")
        }
        return String(localized: "\(name), \(displayPercent) percent")
    }
}

/// Build-once snapshot consumed by HeroMetricTrio. Constructed
/// async in HomeView so the view body stays synchronous.
struct HeroMetricSnapshot: Equatable, Sendable {
    let adherence: HeroMetricValue
    let recovery: HeroMetricValue
    let sleep: HeroMetricValue
    let healthConnected: Bool
    /// Recovery score breakdown captured at build time so the
    /// detail sheet can show "HRV vs baseline / Sleep vs target /
    /// RHR vs baseline" without re-running the HealthKit reads.
    /// Nil when HealthKit isn't connected or the score couldn't be
    /// computed.
    let recoveryComponents: RecoveryScoreEngine.Components?
    /// Last-night sleep duration in hours, captured for the same
    /// reason — the sleep detail sheet shows "Slept N h" without a
    /// second HealthKit hop.
    let lastSleepHours: Double?

    func value(for kind: HeroMetricKind) -> HeroMetricValue {
        switch kind {
        case .adherence: adherence
        case .recovery: recovery
        case .sleep: sleep
        }
    }

    /// True when Recovery or Sleep are unavailable AND the user
    /// hasn't connected HealthKit. Drives the footer prompt. Once
    /// they connect, missing values come from "no recent samples"
    /// rather than "permissions denied" — different copy.
    var needsHealthConnection: Bool {
        !healthConnected && (!recovery.isAvailable || !sleep.isAvailable)
    }

    /// Connected, but Recovery or Sleep has no recent samples to score.
    var awaitsHealthData: Bool {
        healthConnected && (!recovery.isAvailable || !sleep.isAvailable)
    }

    static let empty = HeroMetricSnapshot(
        adherence: .unavailable,
        recovery: .unavailable,
        sleep: .unavailable,
        healthConnected: false,
        recoveryComponents: nil,
        lastSleepHours: nil
    )

    /// A good-but-not-perfect morning for the screenshot demo.
    static let demo = HeroMetricSnapshot(
        adherence: .unavailable,
        recovery: .percent(0.78),
        sleep: .percent(0.86),
        healthConnected: true,
        recoveryComponents: .init(hrv: 0.82, sleep: 0.86, rhr: 0.66),
        lastSleepHours: 6.9
    )

    /// A copy with only the adherence ring changed, so a dose toggle
    /// doesn't repeat the HealthKit reads behind Recovery and Sleep.
    func withAdherence(_ ratio: Double?) -> HeroMetricSnapshot {
        HeroMetricSnapshot(
            adherence: Self.adherenceValue(ratio),
            recovery: recovery,
            sleep: sleep,
            healthConnected: healthConnected,
            recoveryComponents: recoveryComponents,
            lastSleepHours: lastSleepHours
        )
    }

    /// Nothing logged yet reads as no data, not as 0%: a lone empty
    /// ring at breakfast scored the user before the day had started.
    private static func adherenceValue(_ ratio: Double?) -> HeroMetricValue {
        guard let ratio, ratio > 0 else { return .unavailable }
        return .percent(ratio)
    }

    /// Builds the snapshot. Adherence is synchronous (uses the
    /// caller's already-computed ratio, `nil` on a day with no doses
    /// scheduled; with none of them logged yet the ring is left out
    /// rather than reading 0%); Recovery
    /// and Sleep pull from HealthKit via `RecoveryScoreEngine`. Safe to call from
    /// `.task` in HomeView — the call sites batch their work so a
    /// scene-phase change re-runs once, not three times.
    static func build(
        adherenceRatio: Double?,
        healthConnected: Bool,
        sleepTargetHours: Double = RecoveryScoreEngine.defaultSleepTargetHours
    ) async -> HeroMetricSnapshot {
        let adherence = adherenceValue(adherenceRatio)
        guard healthConnected else {
            return HeroMetricSnapshot(
                adherence: adherence,
                recovery: .unavailable,
                sleep: .unavailable,
                healthConnected: false,
                recoveryComponents: nil,
                lastSleepHours: nil
            )
        }

        let kit = await HealthKitService.shared
        async let recentHRV  = kit.averageHRV(days: 3)
        async let baseHRV    = kit.averageHRV(days: 30)
        async let recentRHR  = kit.averageRestingHeartRate(days: 3)
        async let baseRHR    = kit.averageRestingHeartRate(days: 30)
        async let sleepHours = kit.lastNightSleepHours()

        let inputs = await RecoveryScoreEngine.Inputs(
            recentHRV: recentHRV,
            baselineHRV: baseHRV,
            recentRHR: recentRHR,
            baselineRHR: baseRHR,
            lastSleepHours: sleepHours,
            sleepTargetHours: sleepTargetHours
        )

        let recoveryScore = RecoveryScoreEngine.score(inputs: inputs)
        let recoveryValue: HeroMetricValue = {
            guard let s = recoveryScore else { return .unavailable }
            return .percent(Double(s.value) / 100)
        }()

        let sleepValue: HeroMetricValue = {
            guard let hours = inputs.lastSleepHours, hours > 0 else { return .unavailable }
            return .percent(hours / sleepTargetHours)
        }()

        return HeroMetricSnapshot(
            adherence: adherence,
            recovery: recoveryValue,
            sleep: sleepValue,
            healthConnected: true,
            recoveryComponents: recoveryScore?.components,
            lastSleepHours: inputs.lastSleepHours
        )
    }
}

#Preview("All present") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        HeroMetricTrio(
            snapshot: HeroMetricSnapshot(
                adherence: .percent(0.75),
                recovery: .percent(0.85),
                sleep: .percent(0.82),
                healthConnected: true,
                recoveryComponents: .init(hrv: 0.9, sleep: 0.85, rhr: 0.6),
                lastSleepHours: 7.5
            )
        )
        .padding(Spacing.lg)
    }
    .preferredColorScheme(.dark)
}

#Preview("No health connection") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        HeroMetricTrio(
            snapshot: HeroMetricSnapshot(
                adherence: .percent(0.50),
                recovery: .unavailable,
                sleep: .unavailable,
                healthConnected: false,
                recoveryComponents: nil,
                lastSleepHours: nil
            )
        )
        .padding(Spacing.lg)
    }
    .preferredColorScheme(.dark)
}
