import SwiftUI

/// Full-screen detail for a single weekly summary. Pushed from
/// the Today hero card and the Insights archive. Shows the
/// complete AI text (or offline fallback), every stat the engine
/// computed, and a refresh affordance so the user can retry if
/// the network was down when the original ran.
///
/// Pure of mutation — reads the summary the caller passed in.
/// Refresh hands the request back to `WeeklySummaryService` via
/// the `onRefresh` closure, which performs the mutation against
/// `dataStore.profile` and re-routes the new summary back into
/// the view's `summary` binding. Nil hides refresh — the service
/// only regenerates the current week, so an older recap can't be
/// refreshed in place.
struct WeeklySummaryDetailView: View {
    @Binding var summary: WeeklySummary
    let onRefresh: (() async -> Void)?
    @State private var isRefreshing = false

    private var accent: Color {
        AppColor.recap
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                hero
                statsGrid
                bodyText
                metadataRow
            }
            .padding(Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxxl)
        }
        .background(AppColor.background)
        .navigationTitle("Week recap")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onRefresh {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { @MainActor in
                            isRefreshing = true
                            await onRefresh()
                            isRefreshing = false
                            Haptics.success()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(AppFont.scaled(16, weight: .semibold))
                            .symbolEffect(.rotate, options: .repeating, isActive: isRefreshing)
                    }
                    .disabled(isRefreshing)
                    .accessibilityLabel(isRefreshing ? "Refreshing summary" : "Refresh summary")
                }
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(accent)
                        .frame(width: 64, height: 64)
                    Image(systemName: "chart.bar.doc.horizontal.fill")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(AppColor.onAccent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Week recap")
                        .font(AppFont.scaled(11, weight: .heavy))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(accent)
                    Text(weekTitle(for: summary.weekStart))
                        .font(.system(.title2, design: .rounded, weight: .heavy))
                        .foregroundStyle(AppColor.textPrimary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Stats grid

    private var statsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Spacing.sm),
                GridItem(.flexible(), spacing: Spacing.sm),
            ],
            spacing: Spacing.sm
        ) {
            // A week with no scheduled doses has nothing to adhere to.
            if summary.keyStats.dosesTotal > 0 {
                StatTile(
                    label: "Adherence",
                    value: "\(Int((summary.keyStats.compliancePct * 100).rounded()))%",
                    tint: accent,
                    footnote: "\(summary.keyStats.dosesCompleted) of \(summary.keyStats.dosesTotal) doses",
                    size: .large
                )
            }
            StatTile(
                label: "Streak",
                value: "\(summary.keyStats.currentStreak)",
                tint: AppColor.streak,
                footnote: summary.keyStats.currentStreak == 1 ? "day" : "days",
                size: .large
            )
            if let composite = summary.keyStats.avgCheckInScore {
                StatTile(
                    label: "Check-in",
                    value: composite.formatted(.number.precision(.fractionLength(1))),
                    tint: AppColor.metricHRV,
                    footnote: "of 5.0",
                    size: .large
                )
            }
            if let calories = summary.keyStats.avgCalories {
                StatTile(
                    label: "Avg kcal",
                    value: "\(calories)",
                    tint: AppColor.macroProtein,
                    footnote: "per day",
                    size: .large
                )
            }
            if let delta = summary.keyStats.hrvDelta {
                let prefix = delta > 0 ? "+" : ""
                StatTile(
                    label: "HRV Δ",
                    value: "\(prefix)\(delta)",
                    tint: delta >= 0
                        ? AppColor.positive
                        : AppColor.negative,
                    footnote: "ms vs prior week",
                    size: .large
                )
            }
        }
    }

    // MARK: - Body

    private var bodyText: some View {
        GlassCard {
            Text(summary.text)
                .font(AppFont.scaled(16))
                .foregroundStyle(AppColor.textPrimary)
                .lineSpacing(5)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Metadata footer

    private var metadataRow: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: summary.kind == .ai ? "sparkles" : "wifi.slash")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
            Text(metadataText)
                .font(AppFont.scaled(11))
                .foregroundStyle(AppColor.textTertiary)
            Spacer(minLength: 0)
        }
    }

    private var metadataText: String {
        let kindLabel = summary.kind == .ai
            ? String(localized: "Personalised by AI")
            : String(localized: "Offline summary — try refreshing")
        let generated = summary.generatedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(kindLabel) · \(generated)"
    }

    // MARK: - Date helper

    /// Static so `body` doesn't allocate a formatter on every render.
    private static let weekStartParser: ISO8601DateFormatter = {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withFullDate]
        return parser
    }()

    private func weekTitle(for isoWeekStart: String) -> String {
        guard let date = Self.weekStartParser.date(from: isoWeekStart) else {
            return String(localized: "Week recap")
        }
        let display = date.formatted(.dateTime.month(.wide).day())
        return String(format: String(localized: "Week of %@"), display)
    }
}
