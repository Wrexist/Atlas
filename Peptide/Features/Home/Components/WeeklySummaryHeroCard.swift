import SwiftUI

/// Premium Sunday-recap card surfaced on Today when a fresh
/// weekly summary is available for the current ISO week. Three
/// visual states layered over the same accent gradient so the
/// surface stays recognisable as "your week" regardless of which
/// branch the data lands on:
///
///   • `.loading`   — shimmer skeleton over the card chrome while
///                    `WeeklySummaryService.generate(...)` is in
///                    flight. ~1-3 s typical, with proper Reduce
///                    Motion respect via the shared shimmer
///                    modifier.
///   • `.ready`     — full recap: hero glyph, eyebrow + title,
///                    truncated paragraph, four stat tiles, "Read
///                    full recap →" CTA. Tap pushes the detail.
///   • `.empty`     — engine returned `nil` (insufficient data).
///                    Encouraging nudge to keep logging; suppresses
///                    the rest of the card chrome.
///   • `.failed`    — the recap service couldn't be reached. Says so
///                    and offers Try again, instead of blaming the
///                    user's data.
struct WeeklySummaryHeroCard: View {
    let state: State
    let onTap: () -> Void
    let onRetry: (() -> Void)?

    enum State {
        case loading
        case ready(WeeklySummary)
        case empty
        case failed
    }

    private var accent: Color {
        // Cool blue → purple. Pairs with the Insights tab tinting
        // so the card visually signals "review surface", and
        // distinguishes itself from the warm-orange Today
        // Overview Card directly beneath.
        AppColor.recap
    }

    var body: some View {
        Group {
            switch state {
            case .loading:    loadingCard
            case .ready(let summary): readyCard(summary)
            case .empty:      emptyCard
            case .failed:     failedCard
            }
        }
        .transition(.opacity)
        .appAnimation(AppAnimation.settle, value: stateKey)
    }

    private var stateKey: Int {
        switch state {
        case .loading: 0
        case .ready:   1
        case .empty:   2
        case .failed:  3
        }
    }

    // MARK: - Loading

    private var loadingCard: some View {
        GlassCard(tinted: true) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                eyebrowRow(badge: nil)
                heroRow(title: "Reading your week…", aiBadge: false)

                VStack(alignment: .leading, spacing: 8) {
                    // Widths trail off like a paragraph without
                    // overflowing a narrow card.
                    SkeletonBlock()
                    SkeletonBlock().padding(.trailing, Spacing.xxxxl)
                    SkeletonBlock().padding(.trailing, 64)
                }
                .padding(.top, Spacing.xs)
            }
        }
        .overlay(accentBackdrop)
        .accessibilityLabel("Loading your weekly summary")
    }

    // MARK: - Ready

    private func readyCard(_ summary: WeeklySummary) -> some View {
        Button(action: onTap) {
            GlassCard(tinted: true) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    eyebrowRow(badge: summary.kind == .offline ? "OFFLINE" : nil)
                    heroRow(
                        title: weekTitle(for: summary.weekStart),
                        aiBadge: summary.kind == .ai
                    )

                    Text(truncated(summary.text, to: 280))
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Spacing.xs)

                    statsRow(summary.keyStats)
                        .padding(.top, Spacing.xs)

                    HStack(spacing: Spacing.xs) {
                        Text("Read full recap")
                            .font(AppFont.scaled(13, weight: .heavy))
                            .tracking(0.4)
                            .textCase(.uppercase)
                        Image(systemName: "arrow.right")
                            .font(AppFont.scaled(11, weight: .heavy))
                    }
                    .foregroundStyle(accent)
                    .padding(.top, Spacing.xs)
                }
            }
            .overlay(accentBackdrop)
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.985))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weekly summary, \(weekTitle(for: summary.weekStart))")
        .accessibilityHint("Double-tap to read the full recap")
    }

    // MARK: - Empty

    private var emptyCard: some View {
        messageCard(
            title: "Your weekly recap will appear here",
            message: "Log workouts, meals or a check-in on a few more days and your recap appears here."
        )
    }

    // MARK: - Failed

    private var failedCard: some View {
        messageCard(
            title: "Couldn't reach the recap service",
            message: "Your data is safe. Check your connection and try again."
        )
    }

    private func messageCard(title: String, message: LocalizedStringKey) -> some View {
        GlassCard(tinted: true) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                eyebrowRow(badge: nil)
                heroRow(title: title, aiBadge: false)
                Text(message)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.xs)
                if let onRetry {
                    Button(action: onRetry) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "arrow.clockwise")
                                .font(AppFont.scaled(11, weight: .heavy))
                            Text("Try again")
                                .font(AppFont.scaled(13, weight: .heavy))
                                .tracking(0.4)
                                .textCase(.uppercase)
                        }
                        .foregroundStyle(accent)
                    }
                    .buttonStyle(ScalePressStyle())
                    .minimumHitArea()
                }
            }
        }
        .overlay(accentBackdrop)
    }

    // MARK: - Shared chrome

    /// Soft corner glow drawn over the card so the cool-blue
    /// tint reads even on devices with a warm display profile.
    /// `allowsHitTesting(false)` so the tap target stays the
    /// whole card area underneath.
    private var accentBackdrop: some View {
        RadialGradient(
            colors: [accent.opacity(0.22), Color.clear],
            center: .init(x: 0.92, y: -0.10),
            startRadius: 0,
            endRadius: 240
        )
        .allowsHitTesting(false)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
    }

    private func eyebrowRow(badge: String?) -> some View {
        HStack(spacing: Spacing.sm) {
            Text("Week recap")
                .font(AppFont.scaled(11, weight: .heavy))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(accent)
            Spacer(minLength: 0)
            if let badge {
                // The previous treatment (textSecondary on a hairline
                // outline) blended into the tinted card on bright
                // displays — users didn't see the offline marker
                // (audit Biology L19). Foreground on a filled capsule
                // with an icon makes it unmissable without screaming.
                HStack(spacing: 3) {
                    Image(systemName: "wifi.slash")
                        .font(AppFont.scaled(8, weight: .heavy))
                    Text(badge)
                        .font(AppFont.scaled(11, weight: .heavy))
                        .tracking(0.8)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .foregroundStyle(AppColor.textPrimary)
                .background {
                    Capsule()
                        .fill(AppColor.surfaceSecondary.opacity(0.9))
                        .overlay {
                            Capsule()
                                .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                        }
                }
            }
        }
    }

    private func heroRow(title: String, aiBadge: Bool) -> some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(accent)
                    .frame(width: 44, height: 44)
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .font(AppFont.scaled(16, weight: .heavy))
                    .foregroundStyle(AppColor.onAccent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.scaled(20, weight: .heavy, design: .rounded, relativeTo: .title3))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                if aiBadge {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(AppFont.scaled(8, weight: .heavy))
                        Text("Personalised by AI")
                            .font(AppFont.scaled(11, weight: .semibold))
                    }
                    .foregroundStyle(accent.opacity(0.95))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func statsRow(_ stats: WeeklySummary.KeyStats) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Spacing.sm),
                GridItem(.flexible(), spacing: Spacing.sm),
            ],
            spacing: Spacing.sm
        ) {
            // Fitness-only weeks have no doses; "0%" would read as failure.
            if stats.dosesTotal > 0 {
                StatTile(
                    label: "Adherence",
                    value: "\(Int((stats.compliancePct * 100).rounded()))%",
                    tint: accent
                )
            }
            StatTile(
                label: "Streak",
                value: stats.currentStreak == 1 ? "1 day" : "\(stats.currentStreak) days",
                tint: AppColor.streak
            )
            if let composite = stats.avgCheckInScore {
                StatTile(
                    label: "Check-in",
                    value: String(format: "%.1f", composite),
                    tint: AppColor.metricHRV
                )
            }
            if let calories = stats.avgCalories {
                StatTile(
                    label: "Avg kcal",
                    value: "\(calories)",
                    tint: AppColor.macroProtein
                )
            }
            if let delta = stats.hrvDelta {
                let prefix = delta > 0 ? "+" : ""
                StatTile(
                    label: "HRV Δ",
                    value: "\(prefix)\(delta) ms",
                    tint: delta >= 0
                        ? AppColor.positive
                        : AppColor.negative
                )
            }
        }
    }

    // MARK: - Helpers

    /// Renders "Week of Jan 5" given an ISO yyyy-MM-dd weekStart, with
    /// the month/day order following the user's locale.
    private func weekTitle(for isoWeekStart: String) -> String {
        guard let date = WeeklySummaryEngine.weekStartDate(from: isoWeekStart) else {
            return String(localized: "This week")
        }
        let display = date.formatted(.dateTime.month(.abbreviated).day())
        return String(format: String(localized: "Week of %@"), display)
    }

    /// Truncates the AI paragraph for the card preview. Splits on
    /// sentence boundary when possible so the cut doesn't fall
    /// mid-word — the detail view has the full text.
    private func truncated(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let prefix = text.prefix(limit)
        if let lastPeriod = prefix.lastIndex(of: ".") {
            return String(prefix[..<lastPeriod]) + "…"
        }
        return String(prefix) + "…"
    }
}

#Preview("Ready (AI)") {
    ScrollView {
        WeeklySummaryHeroCard(
            state: .ready(
                WeeklySummary(
                    weekStart: "2026-01-05",
                    text: "Strong week — 19 of 21 doses logged (90 % compliance) and a 12-day streak. Your check-ins averaged 4.1 of 5, holding steady alongside an HRV that climbed 4 ms versus the prior week. Keep the cadence steady next week; consistency at this level tends to compound.",
                    keyStats: .init(
                        compliancePct: 0.905,
                        dosesCompleted: 19,
                        dosesTotal: 21,
                        currentStreak: 12,
                        avgCheckInScore: 4.1,
                        avgCalories: 2380,
                        hrvDelta: 4
                    ),
                    kind: .ai,
                    generatedAt: Date()
                )
            ),
            onTap: {},
            onRetry: nil
        )
        .padding(Spacing.screenPadding)
    }
    .background(AppColor.background)
    .preferredColorScheme(.dark)
}

#Preview("Loading") {
    ScrollView {
        WeeklySummaryHeroCard(state: .loading, onTap: {}, onRetry: nil)
            .padding(Spacing.screenPadding)
    }
    .background(AppColor.background)
    .preferredColorScheme(.dark)
}

#Preview("Empty") {
    ScrollView {
        WeeklySummaryHeroCard(state: .empty, onTap: {}, onRetry: {})
            .padding(Spacing.screenPadding)
    }
    .background(AppColor.background)
    .preferredColorScheme(.dark)
}
