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
                .foregroundStyle(AppColor.textPrimary)
            Text("As of \(Self.asOfFormatter.string(from: asOfDate))")
                .font(AppFont.scaled(15, weight: .medium))
                .foregroundStyle(AppColor.textPrimary.opacity(0.55))
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
                .foregroundStyle(AppColor.textPrimary.opacity(0.7))
            Text("Building")
                .font(AppFont.scaled(13, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(AppColor.textPrimary.opacity(0.7))
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(AppColor.accentLight)
                .frame(width: 140)
        }
    }

    private func unlockedCentre(estimate: PerformanceAgeEngine.Estimate) -> some View {
        // Big number with cosmic glow + sign-tinted color so the
        // "younger than chronological" / "older than chronological"
        // story reads in the first 200ms of glance time. Glow uses
        // the same accent tint as the number, dialled down so it
        // suggests depth without competing with the cosmic
        // backdrop.
        let isYounger = estimate.biologicalAge < Double(chronologicalAge)
        let tint = unlockedTint(isYounger: isYounger)
        return Text(Self.bigNumberFormatter.string(from: NSNumber(value: estimate.biologicalAge)) ?? "—")
            .font(.system(size: 56, weight: .heavy, design: .rounded))
            .foregroundStyle(tint)
            .monospacedDigit()
            .contentTransition(.numericText())
            // A neutral drop, not a tinted halo. Two stacked coloured
            // shadows behind a 56pt number read as neon; the number already
            // carries its own colour, and legibility over the starfield only
            // needs the backdrop pushed away from it.
            .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
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
                    .font(AppFont.scaled(11, weight: .heavy))
                Text("Unlock with Pro")
                    .font(AppFont.scaled(13, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(AppColor.textPrimary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 8)
            .background {
                Capsule().fill(AppColor.textPrimary.opacity(0.18))
                    .overlay {
                        Capsule().strokeBorder(AppColor.textPrimary.opacity(0.30), lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.95))
        .accessibilityLabel("Unlock biological age with Pro")
    }

    private func buildingLabel(progress: Double) -> some View {
        // `progress` from BioAgeStateResolver is `dataDays / minBaselineDays`
        // — a fraction of the 7-day baseline *window*, NOT a fraction of the
        // three HRV/RHR/Sleep signals. The earlier "× 3 signals connected"
        // copy mapped this day-fraction onto a 0…3 signal axis, so a user
        // with 4/7 days saw "2 of 3 signals connected" regardless of which
        // HealthKit types responded. Render the day count it represents,
        // keyed off `minBaselineDays` so the two never drift apart.
        let total = BioAgeStateResolver.minBaselineDays
        let days = max(0, min(total, Int((progress * Double(total)).rounded())))
        return Text("\(days) of \(total) days of data collected")
            .font(AppFont.scaled(13, weight: .medium))
            .foregroundStyle(AppColor.textPrimary.opacity(0.55))
    }

    private func unlockedBigNumber(estimate: PerformanceAgeEngine.Estimate) -> some View {
        // Below the dial: delta-from-chronological badge + drivers
        // preview. "4 years younger" is the headline; the drivers
        // pills are the small print explaining what's moving it.
        VStack(spacing: Spacing.sm) {
            deltaBadge(for: estimate)
            if !estimate.drivers.isEmpty {
                driversPreview(estimate: estimate)
            }
        }
    }

    private func deltaBadge(for estimate: PerformanceAgeEngine.Estimate) -> some View {
        let delta = estimate.biologicalAge - Double(chronologicalAge)
        let absDelta = abs(delta)
        let absRounded = absDelta < 0.05 ? 0 : absDelta
        let isYounger = delta < 0
        let tint = unlockedTint(isYounger: isYounger)
        let label: String = {
            if absRounded == 0 {
                return String(localized: "Matching your age")
            }
            let formatted = String(format: "%.1f", absRounded)
            return isYounger
                ? String(format: String(localized: "%@ years younger"), formatted)
                : String(format: String(localized: "%@ years older"), formatted)
        }()
        let icon = absRounded == 0
            ? "equal.circle.fill"
            : (isYounger ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
        return HStack(spacing: 5) {
            Image(systemName: icon)
                .font(AppFont.scaled(12, weight: .heavy))
            Text(label)
                .font(AppFont.scaled(13, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
        .background {
            Capsule().fill(tint.opacity(0.18))
                .overlay {
                    Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5)
                }
        }
    }

    private func driversPreview(estimate: PerformanceAgeEngine.Estimate) -> some View {
        // Top three contributors by absolute impact. Drivers are
        // already sorted by the engine; we just trim. Each pill
        // shows the kind + signed delta in years so the user
        // reads "HRV −2.5y / Sleep +1.5y / RHR −1.8y" at a
        // glance.
        HStack(spacing: Spacing.xs) {
            ForEach(estimate.drivers.prefix(3)) { driver in
                driverPill(driver)
            }
        }
        .padding(.horizontal, Spacing.lg)
    }

    private func driverPill(_ driver: PerformanceAgeEngine.Driver) -> some View {
        let isYounger = driver.deltaYears < 0
        let signed = String(format: "%@%.1fy",
                            driver.deltaYears > 0 ? "+" : "",
                            driver.deltaYears)
        return HStack(spacing: 3) {
            Image(systemName: driverIcon(for: driver.kind))
                .font(AppFont.scaled(9, weight: .heavy))
            Text(driverLabel(for: driver.kind))
                .font(AppFont.scaled(10, weight: .heavy, design: .rounded))
                .tracking(0.3)
            Text(signed)
                .font(AppFont.scaled(10, weight: .heavy))
                .monospacedDigit()
        }
        .foregroundStyle(unlockedTint(isYounger: isYounger).opacity(0.95))
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 4)
        .background {
            Capsule().fill(AppColor.textPrimary.opacity(0.08))
                .overlay {
                    Capsule().strokeBorder(AppColor.textPrimary.opacity(0.10), lineWidth: 0.5)
                }
        }
    }

    private func driverIcon(for kind: PerformanceAgeEngine.Driver.Kind) -> String {
        switch kind {
        case .hrv:    return "waveform.path.ecg"
        case .rhr:    return "heart.fill"
        case .sleep:  return "bed.double.fill"
        case .weight: return "scalemass.fill"
        }
    }

    private func driverLabel(for kind: PerformanceAgeEngine.Driver.Kind) -> String {
        switch kind {
        case .hrv:    return "HRV"
        case .rhr:    return "RHR"
        case .sleep:  return "SLEEP"
        case .weight: return "WEIGHT"
        }
    }

    /// Tint applied to the big bio-age number, the delta badge,
    /// and the driver pills. Green when younger / matching; warm
    /// orange when older. Saturated enough that the cosmic
    /// backdrop doesn't wash them out.
    private func unlockedTint(isYounger: Bool) -> Color {
        isYounger
            ? AppColor.positive
            : AppColor.negative
    }

    // MARK: - Formatters

    private static let asOfFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f
    }()

    private static let bigNumberFormatter: NumberFormatter = {
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
