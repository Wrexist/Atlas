import SwiftUI

/// Top of the Biology tab. Three states:
///
///   • `.locked` — free tier: shows the dial outline + scale +
///     particle cluster where the needle would go, plus a
///     "Unlock with Pro" capsule. Aspirational, not punitive —
///     the user sees what they could have.
///   • `.building(progress:)` — Pro tier but < 7 days of HealthKit
///     data: shows "Building your baseline" with a progress bar.
///     Encouragement, not failure.
///   • `.unlocked(estimate:)` — Pro tier + sufficient data: real
///     bio age render with the needle at position and the big
///     number underneath. The full surface lands in commit 7;
///     this commit ships the case but with a "Coming next" hint
///     so the unlocked path doesn't crash if a tester forces
///     it via debug toggles.
///
/// Commit 7 wires the actual state determination — for now this
/// view's host (BiologyView) hardcodes `.locked` since the
/// PerformanceAgeEngine plumbing into BiologyView lands with the
/// BiologyConfig persistence work.
struct BioAgeHeroSection: View {
    let state: BioAgeState
    let chronologicalAge: Int
    let asOfDate: Date
    var onUnlockTapped: () -> Void = {}

    enum BioAgeState: Equatable, Sendable {
        case locked
        case building(progress: Double)               // 0…1, share of 7-day baseline collected
        case unlocked(estimate: PerformanceAgeEngine.Estimate)
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            header
            dialStack
            stateAffordance
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.lg)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            Text("Biological Age")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("As of \(Self.asOfFormatter.string(from: asOfDate))")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
        }
    }

    // MARK: - Dial + centre content

    private var dialStack: some View {
        ZStack {
            BioAgeDial(
                chronologicalAge: chronologicalAge,
                bioAge: dialNeedleValue,
                size: 280
            )
            centreContent
        }
        .frame(height: 280)
    }

    private var dialNeedleValue: Double? {
        switch state {
        case .locked, .building:                       return nil
        case .unlocked(let estimate):                  return estimate.biologicalAge
        }
    }

    @ViewBuilder
    private var centreContent: some View {
        switch state {
        case .locked:
            BioAgeParticleCluster(size: 200)
        case .building(let progress):
            buildingCentre(progress: progress)
        case .unlocked(let estimate):
            unlockedCentre(estimate: estimate)
        }
    }

    private func buildingCentre(progress: Double) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "hourglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.white.opacity(0.7))
            Text("Building")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.7))
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(AppColor.accentLight)
                .frame(width: 140)
        }
    }

    private func unlockedCentre(estimate: PerformanceAgeEngine.Estimate) -> some View {
        // Detail rendering ships in commit 7 alongside the
        // confidence-driven state determination. For now: a
        // minimum-viable big-number so a tester forcing the
        // .unlocked case via a debug builds doesn't see an
        // empty centre. Final styling (cosmic glow underneath,
        // delta-from-chronological badge, drivers preview) is
        // commit 7's job.
        Text(Self.bigNumberFormatter.string(from: NSNumber(value: estimate.biologicalAge)) ?? "—")
            .font(.system(size: 56, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    // MARK: - State affordance (Pro pill / progress label / value below)

    @ViewBuilder
    private var stateAffordance: some View {
        switch state {
        case .locked:
            unlockPill
        case .building(let progress):
            buildingLabel(progress: progress)
        case .unlocked(let estimate):
            unlockedBigNumber(estimate: estimate)
        }
    }

    private var unlockPill: some View {
        Button(action: onUnlockTapped) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .heavy))
                Text("Unlock with Pro")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 8)
            .background {
                Capsule().fill(Color.white.opacity(0.18))
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.95))
        .accessibilityLabel("Unlock biological age with Pro")
    }

    private func buildingLabel(progress: Double) -> some View {
        let days = Int((progress * 7).rounded())
        return Text("\(days) of 7 days of baseline collected")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.55))
    }

    private func unlockedBigNumber(estimate: PerformanceAgeEngine.Estimate) -> some View {
        Text(Self.bigNumberFormatter.string(from: NSNumber(value: estimate.biologicalAge)) ?? "—")
            .font(.system(size: 44, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .monospacedDigit()
    }

    // MARK: - Formatters

    nonisolated(unsafe) private static let asOfFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f
    }()

    nonisolated(unsafe) private static let bigNumberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return f
    }()
}

#Preview("Locked") {
    ZStack {
        CosmicBackdrop(intensity: 0.55).ignoresSafeArea()
        BioAgeHeroSection(
            state: .locked,
            chronologicalAge: 26,
            asOfDate: Date()
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Building (4 of 7 days)") {
    ZStack {
        CosmicBackdrop(intensity: 0.55).ignoresSafeArea()
        BioAgeHeroSection(
            state: .building(progress: 4.0 / 7.0),
            chronologicalAge: 26,
            asOfDate: Date()
        )
    }
    .preferredColorScheme(.dark)
}
