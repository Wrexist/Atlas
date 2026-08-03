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
/// the view's `summary` binding.
struct WeeklySummaryDetailView: View {
    @Binding var summary: WeeklySummary
    let onRefresh: () async -> Void
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
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { @MainActor in
                        isRefreshing = true
                        await onRefresh()
                        isRefreshing = false
                    }
                } label: {
                    Image(systemName: isRefreshing
                          ? "arrow.clockwise.circle"
                          : "arrow.clockwise")
                        .font(AppFont.scaled(16, weight: .semibold))
                        .symbolEffect(.rotate, value: isRefreshing)
                }
                .disabled(isRefreshing)
                .accessibilityLabel("Refresh summary")
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.65)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: accent.opacity(0.45), radius: 12, y: 6)
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
            statTile(
                label: "Compliance",
                value: "\(Int((summary.keyStats.compliancePct * 100).rounded()))%",
                sublabel: "\(summary.keyStats.dosesCompleted) of \(summary.keyStats.dosesTotal) doses",
                tint: accent
            )
            statTile(
                label: "Streak",
                value: "\(summary.keyStats.currentStreak)",
                sublabel: summary.keyStats.currentStreak == 1 ? "day" : "days",
                tint: AppColor.streak
            )
            if let composite = summary.keyStats.avgCheckInScore {
                statTile(
                    label: "Check-in",
                    value: String(format: "%.1f", composite),
                    sublabel: "of 5.0",
                    tint: AppColor.metricHRV
                )
            }
            if let calories = summary.keyStats.avgCalories {
                statTile(
                    label: "Avg kcal",
                    value: "\(calories)",
                    sublabel: "per day",
                    tint: AppColor.macroProtein
                )
            }
            if let delta = summary.keyStats.hrvDelta {
                let prefix = delta > 0 ? "+" : ""
                statTile(
                    label: "HRV Δ",
                    value: "\(prefix)\(delta)",
                    sublabel: "ms vs prior week",
                    tint: delta >= 0
                        ? AppColor.positive
                        : AppColor.negative
                )
            }
        }
    }

    private func statTile(
        label: LocalizedStringKey,
        value: String,
        sublabel: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppFont.scaled(11, weight: .heavy))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.textSecondary)
            Text(value)
                .font(.system(.title, design: .rounded, weight: .heavy))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(sublabel)
                .font(AppFont.scaled(11))
                .foregroundStyle(AppColor.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.cardOverlay)
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
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
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(kindLabel) · \(formatter.string(from: summary.generatedAt))"
    }

    // MARK: - Date helper

    private func weekTitle(for isoWeekStart: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withFullDate]
        guard let date = parser.date(from: isoWeekStart) else {
            return String(localized: "Week recap")
        }
        let display = DateFormatter()
        display.dateFormat = "MMMM d"
        display.locale = .current
        return String(format: String(localized: "Week of %@"), display.string(from: date))
    }
}
