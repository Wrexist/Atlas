import SwiftUI
import Charts

/// Tap-a-row drill-down. One sheet, one Chart, one big number,
/// one "vs your 30-day average" delta line, one footnote naming
/// the data source. Same shell pattern as `HeroMetricDetailSheet`
/// so the user's mental model carries across surfaces.
///
/// Series is fetched async from `BiomarkerSeriesService`'s
/// daily-90-day helpers. The view degrades gracefully when fewer
/// than 7 days of history exist — the chart hides and a "Need
/// more data" placeholder takes its slot.
struct BiomarkerDetailSheet: View {
    let biomarker: Biomarker
    /// Initial 14-day snapshot the host hands in for instant
    /// render. The sheet upgrades to a 90-day snapshot via the
    /// fetcher closure on appear so the chart fills out as soon
    /// as HealthKit / store reads land.
    let initialSnapshot: BiomarkerSnapshot
    /// Async fetch closure the host wires to a service call.
    /// Returns a wider-window snapshot (typically 90 days) so the
    /// chart and "vs recent average" surfaces have more history.
    /// Nil → the sheet renders from `initialSnapshot` only.
    var historicalFetcher: (() async -> BiomarkerSnapshot?)?

    @State private var historicalSnapshot: BiomarkerSnapshot?
    @Environment(\.dismiss) private var dismiss

    /// What the rest of the view reads — the larger window if the
    /// fetch succeeded, otherwise the instant initial snapshot
    /// the host handed in.
    private var snapshot: BiomarkerSnapshot {
        historicalSnapshot ?? initialSnapshot
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    heroBlock
                    explainer
                    chartBlock
                    deltaBlock
                    footnote
                }
                .padding(Spacing.screenPadding)
            }
            .background(AppColor.background)
            .navigationTitle(biomarker.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                // Upgrade from the host's 14-day snapshot to the
                // 90-day series for the chart. If the fetcher is
                // nil or returns nil (no data / HealthKit blocked),
                // we keep rendering the initial snapshot.
                guard historicalSnapshot == nil,
                      let fetcher = historicalFetcher else { return }
                if let larger = await fetcher() {
                    historicalSnapshot = larger
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Hero

    private var heroBlock: some View {
        HStack(alignment: .lastTextBaseline, spacing: Spacing.sm) {
            Text(latestValueString)
                .font(.system(size: 48, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
            if let unit = biomarker.unit {
                Text(unit)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: 0)
            trendChip
        }
    }

    private var latestValueString: String {
        guard let latest = snapshot.latest else { return "—" }
        return BiomarkerSeriesService.formatValue(latest, for: biomarker)
    }

    private var trendChip: some View {
        let (label, icon, tint): (String, String, Color) = {
            switch snapshot.trend {
            case .up:           return ("Trending up",   "arrow.up.circle.fill",   AppColor.success)
            case .down:         return ("Trending down", "arrow.down.circle.fill", AppColor.macroWaterLight)
            case .flat:         return ("Steady",        "equal.circle.fill",      AppColor.textSecondary)
            case .insufficient: return ("Not enough data", "minus.circle.fill",    AppColor.textTertiary)
            }
        }()
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .heavy))
            Text(label)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 5)
        .background {
            Capsule().fill(tint.opacity(0.15))
        }
    }

    // MARK: - Explainer

    private var explainer: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("WHAT THIS TRACKS")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(AppColor.accentLight)
            Text(explainerBody)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var explainerBody: String {
        switch biomarker {
        case .weight:
            return String(localized: "Your bodyweight trend. Rapid swings in either direction stress recovery — slow, steady changes are the signal.")
        case .hrvBaseline:
            return String(localized: "Heart-rate variability baseline. Higher HRV generally tracks with better recovery and lower stress.")
        case .rhrBaseline:
            return String(localized: "Your resting heart rate. Lower is typically better — athletes commonly sit in the 50s.")
        case .sleepBaseline:
            return String(localized: "Total time asleep per night. Atlas's recovery score uses 8 hours as a default target.")
        case .stepsBaseline:
            return String(localized: "Daily step count. Loosely correlates with total activity volume.")
        case .bodyTemperature:
            return String(localized: "Wrist temperature deviation. Spikes can signal poor recovery or illness.")
        case .bodyFat:
            return String(localized: "Body fat percentage. Manual log; correlate with weight trend for body-comp context.")
        case .waist:
            return String(localized: "Waist circumference. Often more sensitive than weight for body-comp shifts on a recomp protocol.")
        case .bloodPressure:
            return String(localized: "Resting blood pressure. Manual log; helpful baseline before a new protocol.")
        case .latestLabPanel:
            return String(localized: "Most recent lab marker. Add panels in the Labs section of Insights to track over time.")
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private var chartBlock: some View {
        if snapshot.sparkline.count >= 4 {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("RECENT TREND")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(AppColor.accentLight)

                trendChart
            }
        } else {
            insufficientChartPlaceholder
        }
    }

    private var trendChart: some View {
        Chart {
            ForEach(Array(snapshot.sparkline.enumerated()), id: \.offset) { idx, value in
                trendMarks(idx: idx, value: value)
            }
        }
        .chartXAxis {
            // Stride scales with the window — daily ticks
            // would be unreadable at 90 days, weekly is
            // unreadable at 14, so we pick based on series
            // length.
            AxisMarks(values: .stride(by: axisStride)) { value in
                AxisValueLabel {
                    if let day = value.as(Int.self) {
                        Text(dayLabel(daysAgo: day))
                            .font(.system(size: 10))
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }
                AxisGridLine().foregroundStyle(AppColor.glassBorder)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel()
                    .foregroundStyle(AppColor.textTertiary)
                AxisGridLine().foregroundStyle(AppColor.glassBorder)
            }
        }
        .frame(height: 180)
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
    }

    @ChartContentBuilder
    private func trendMarks(idx: Int, value: Double) -> some ChartContent {
        let day = -snapshot.sparkline.count + idx + 1
        LineMark(
            x: .value("Day", day),
            y: .value(biomarker.displayName, value)
        )
        .interpolationMethod(.monotone)
        .lineStyle(.init(lineWidth: 2, lineCap: .round, lineJoin: .round))
        .foregroundStyle(AppColor.accentPrimary)

        AreaMark(
            x: .value("Day", day),
            y: .value(biomarker.displayName, value)
        )
        .interpolationMethod(.monotone)
        .foregroundStyle(
            LinearGradient(
                colors: [
                    AppColor.accentPrimary.opacity(0.35),
                    AppColor.accentPrimary.opacity(0.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func dayLabel(daysAgo: Int) -> String {
        if daysAgo == 0 { return "Today" }
        if daysAgo == -7 { return "1w" }
        if daysAgo == -14 { return "2w" }
        if daysAgo == -30 { return "1mo" }
        if daysAgo == -60 { return "2mo" }
        if daysAgo == -90 { return "3mo" }
        return "\(abs(daysAgo))d"
    }

    /// Picks an axis stride that produces readable tick labels
    /// across the spectrum of window sizes the sheet might
    /// render — 14 daily samples (initial snapshot) → 2-day
    /// stride, 90 daily samples (historical) → 14-day stride.
    private var axisStride: Int {
        let count = snapshot.sparkline.count
        if count >= 80 { return 14 }
        if count >= 30 { return 7 }
        return 2
    }

    private var insufficientChartPlaceholder: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "hourglass")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(AppColor.textTertiary)
            Text("Need at least 4 days of data to chart a trend.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.45))
        }
    }

    // MARK: - Delta block

    private var deltaBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("VS RECENT AVERAGE")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(AppColor.accentLight)
            Text(deltaLine)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
    }

    private var deltaLine: String {
        guard let latest = snapshot.latest, snapshot.sparkline.count >= 4 else {
            return String(localized: "Log more data to see a comparison.")
        }
        let avg = snapshot.sparkline.reduce(0, +) / Double(snapshot.sparkline.count)
        let delta = latest - avg
        let absDelta = BiomarkerSeriesService.formatValue(abs(delta), for: biomarker)
        let unit = biomarker.unit ?? ""
        if abs(delta) < 0.01 {
            return String(localized: "Right at your recent average.")
        }
        let direction = delta > 0
            ? String(localized: "above")
            : String(localized: "below")
        return String(
            format: String(localized: "%@ %@ %@ your recent average."),
            absDelta, unit, direction
        )
    }

    // MARK: - Footnote

    private var footnote: some View {
        Text(footnoteText)
            .font(.system(size: 11))
            .foregroundStyle(AppColor.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private var footnoteText: String {
        switch biomarker {
        case .hrvBaseline, .rhrBaseline, .sleepBaseline,
             .stepsBaseline, .bodyTemperature:
            return String(localized: "Source: Apple Health")
        case .weight:
            return String(localized: "Source: your weight log")
        case .bodyFat, .waist, .bloodPressure:
            return String(localized: "Source: manual entries")
        case .latestLabPanel:
            return String(localized: "Source: your lab panel")
        }
    }
}

#Preview("HRV — full series") {
    BiomarkerDetailSheet(
        biomarker: .hrvBaseline,
        initialSnapshot: BiomarkerSnapshot(
            biomarker: .hrvBaseline,
            latest: 58,
            trend: .up,
            sparkline: [50, 52, 54, 53, 55, 57, 56, 58, 60, 58, 59, 58, 60, 62],
            changeText: "Trending up · 58 ms"
        )
    )
}

#Preview("Weight — empty") {
    BiomarkerDetailSheet(
        biomarker: .weight,
        initialSnapshot: .empty(.weight)
    )
}
