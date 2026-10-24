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
    /// The user's preferred measurement unit. Snapshots store canonical
    /// metric; the hero number, chart, and delta convert at render so
    /// imperial users see lb / in / °F (audit Biology A4).
    var unit: MeasurementUnit = .metric
    /// Called after the user logs a manual reading, so the host's row
    /// re-reads too.
    var onReadingLogged: (() -> Void)?

    @State private var showEntrySheet = false
    @State private var range: ChartRange = .month
    @State private var historicalSnapshot: BiomarkerSnapshot?
    /// True while the 90-day read is in flight, so a short initial
    /// series shows a loading chart rather than "need more data".
    @State private var isFetching = false
    /// The date the user is scrubbing on the chart.
    @State private var selectedDate: Date?
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
                    // The number and its chart sit together; the static
                    // explainer follows what changes day to day.
                    heroBlock
                    if biomarker.supportsManualEntry {
                        logReadingButton
                    }
                    chartBlock
                    if hasComparison {
                        deltaBlock
                    }
                    explainer
                    footnote
                }
                .padding(Spacing.screenPadding)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle(biomarker.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadHistory() }
            .sheet(isPresented: $showEntrySheet) {
                BodyMeasurementEntrySheet(biomarker: biomarker, unit: unit) {
                    onReadingLogged?()
                    Task { await loadHistory() }
                }
            }
        }
        .presentationSizing(.page)
    }

    /// Upgrades from the host's 14-day snapshot to the 90-day series for
    /// the chart, and re-reads after a logged reading. If the fetcher is
    /// nil or returns nil (no data / HealthKit blocked), the sheet keeps
    /// rendering what it has.
    private func loadHistory() async {
        guard let fetcher = historicalFetcher else { return }
        isFetching = true
        let larger = await fetcher()
        AppAnimation.with(AppAnimation.springSmooth) {
            if let larger { historicalSnapshot = larger }
            isFetching = false
        }
    }

    private var logReadingButton: some View {
        GlassButton(title: "Log a reading", icon: "plus", style: .secondary, isFullWidth: true) {
            Haptics.impact(.light)
            showEntrySheet = true
        }
    }

    // MARK: - Hero

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(alignment: .lastTextBaseline, spacing: Spacing.sm) {
                Text(latestValueString)
                    .font(AppFont.scaled(48, weight: .heavy, design: .rounded, relativeTo: .largeTitle))
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let unitString = biomarker.displayUnit(for: unit) {
                    Text(unitString)
                        .font(AppFont.scaled(16, weight: .heavy))
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: 0)
                trendChip
            }
            HStack(spacing: Spacing.sm) {
                if let latestCaption {
                    Text(latestCaption)
                }
                Spacer(minLength: 0)
                // The sheet upgrades from the row's 14-day snapshot to
                // 90 days, so the chip says which window it reads.
                if snapshot.trend != .insufficient {
                    Text("Last \(trendWindowDays) days")
                }
            }
            .font(AppFont.caption2)
            .foregroundStyle(AppColor.textSecondary)
        }
    }

    /// When the hero number was recorded, so an old reading never
    /// passes for today's.
    private var latestCaption: String? {
        guard let latestDate = snapshot.latestDate else { return nil }
        return snapshot.staleNote() ?? dayLabel(for: latestDate)
    }

    private var trendWindowDays: Int {
        historicalSnapshot == nil ? BiomarkerSeriesService.windowDays : BiomarkerSeriesService.detailWindowDays
    }

    private var latestValueString: String {
        guard let latest = snapshot.latest else { return "—" }
        if let diastolic = snapshot.latestSecondary {
            return BiomarkerSeriesService.bloodPressureText(systolic: latest, diastolic: diastolic)
        }
        return BiomarkerSeriesService.formatValue(biomarker.displayValue(latest, for: unit), for: biomarker)
    }

    /// Direction only, in neutral ink: whether "up" is good depends on the
    /// biomarker (rising HRV vs rising resting heart rate), so the chip
    /// doesn't claim either.
    private var trendChip: some View {
        let (label, icon, tint): (LocalizedStringKey, String, Color) = {
            switch snapshot.trend {
            case .up:           return ("Trending up",   "arrow.up.circle.fill",   AppColor.textSecondary)
            case .down:         return ("Trending down", "arrow.down.circle.fill", AppColor.textSecondary)
            case .flat:         return ("Steady",        "equal.circle.fill",      AppColor.textSecondary)
            case .insufficient: return ("Not enough data", "minus.circle.fill",    AppColor.textTertiary)
            }
        }()
        return HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(AppFont.scaled(11, weight: .heavy))
            Text(label)
                .font(AppFont.scaled(11, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background {
            Capsule().fill(tint.opacity(0.15))
        }
    }

    // MARK: - Explainer

    private var explainer: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("What this tracks")
                .textCase(.uppercase)
                .font(AppFont.eyebrow)
                .tracking(1.0)
                .foregroundStyle(AppColor.textSecondary)
                .accessibilityAddTraits(.isHeader)
            Text(explainerBody)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let reference = biomarker.reference {
                Link(destination: reference.url) {
                    Label("Learn more · \(reference.publisher)", systemImage: "arrow.up.right")
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.accentLight)
                        .minimumHitArea()
                }
                .padding(.top, Spacing.xxs)
            }
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
            return String(localized: "Total time asleep per night. It feeds both your recovery score and your Biological Age.")
        case .stepsBaseline:
            return String(localized: "Daily step count. Loosely correlates with total activity volume.")
        case .bodyTemperature:
            return String(localized: "Your body temperature. Spikes above your usual reading can signal poor recovery or illness.")
        case .bodyFat:
            return String(localized: "Body fat percentage. Manual log; correlate with weight trend for body-comp context.")
        case .waist:
            return String(localized: "Waist circumference. Often more sensitive than weight for body-comp shifts on a recomp protocol.")
        case .bloodPressure:
            return String(localized: "Resting blood pressure. Manual log; helpful baseline before a new protocol.")
        case .latestLabPanel:
            return String(localized: "Most recent lab marker. Add results in Labs on the Biology tab to track over time.")
        }
    }

    // MARK: - Chart

    /// The chart's window. The sheet reads 90 days once; the shorter
    /// ranges are cuts of that series, so switching is instant.
    enum ChartRange: Int, CaseIterable {
        case week = 7
        case month = 30
        case quarter = 90

        var label: LocalizedStringKey {
            switch self {
            case .week:    "7 days"
            case .month:   "30 days"
            case .quarter: "90 days"
            }
        }
    }

    /// Readings inside the chosen range, counted back from today.
    private func inRange(_ samples: [BiomarkerSnapshot.Sample]) -> [BiomarkerSnapshot.Sample] {
        let today = Calendar.current.startOfDay(for: Date())
        guard let start = Calendar.current.date(byAdding: .day, value: 1 - range.rawValue, to: today) else { return samples }
        return samples.filter { $0.date >= start }
    }

    private var chartSamples: [BiomarkerSnapshot.Sample] { inRange(snapshot.samples) }
    private var chartSecondarySamples: [BiomarkerSnapshot.Sample] { inRange(snapshot.secondarySamples) }

    /// Mean of the charted readings in display units. Blood pressure has
    /// none: a systolic-only mean would read as the whole pressure.
    private var chartMean: Double? {
        let values = chartSamples.map { biomarker.displayValue($0.value, for: unit) }
        guard snapshot.secondarySamples.isEmpty, !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    @ViewBuilder
    private var chartBlock: some View {
        if snapshot.samples.count >= Self.minimumSamples {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Recent trend")
                        .textCase(.uppercase)
                        .font(AppFont.eyebrow)
                        .tracking(1.0)
                        .foregroundStyle(AppColor.textSecondary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Spacing.sm)
                    GlassSegmentedControl(
                        options: ChartRange.allCases,
                        selected: $range,
                        label: { $0.label }
                    )
                    .fixedSize()
                }

                if chartSamples.count >= 2 {
                    trendChart
                    chartCaption
                } else {
                    emptyRangePlaceholder
                }
            }
        } else if isFetching {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.55))
                .frame(height: 180 + Spacing.md * 2)
                .shimmer()
                .accessibilityLabel("Loading trend")
        } else {
            insufficientChartPlaceholder
        }
    }

    /// Display-unit domain around the plotted values, so the line uses
    /// the plot's height instead of hugging the top of a zero-based axis.
    private var chartDomain: ClosedRange<Double> {
        let values = (chartSamples + chartSecondarySamples).map { biomarker.displayValue($0.value, for: unit) }
        return ChartYDomain.padded(values, minimumPadding: biomarker.chartMinimumPadding) ?? 0...1
    }

    private var trendChart: some View {
        let domain = chartDomain
        return Chart {
            ForEach(chartSamples, id: \.date) { sample in
                trendMarks(for: sample, floor: domain.lowerBound)
            }
            ForEach(chartSecondarySamples, id: \.date) { sample in
                diastolicMark(for: sample)
            }
            if let chartMean {
                RuleMark(y: .value("Average", chartMean))
                    .foregroundStyle(AppColor.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .accessibilityHidden(true)
            }
            if let selectedSample {
                RuleMark(x: .value("Date", selectedSample.date, unit: .day))
                    .foregroundStyle(AppColor.textTertiary)
                    .lineStyle(.init(lineWidth: 1))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        selectionCallout(for: selectedSample)
                    }
            }
        }
        .chartXSelection(value: $selectedDate)
        .appSensoryFeedback(.selection, trigger: selectedSample?.date)
        .chartXAxis {
            // Stride scales with the window — daily ticks
            // would be unreadable at 90 days, weekly is
            // unreadable at 14, so we pick based on series
            // length.
            AxisMarks(values: .stride(by: .day, count: axisStride)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(dayLabel(for: date))
                            .font(AppFont.scaled(11))
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }
                AxisGridLine().foregroundStyle(AppColor.glassBorder)
            }
        }
        .chartYScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel()
                    .foregroundStyle(AppColor.textTertiary)
                AxisGridLine().foregroundStyle(AppColor.glassBorder)
            }
        }
        .frame(height: 180)
        .padding(Spacing.md)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    /// The reading nearest the scrubbed date, or `nil` when not scrubbing.
    private var selectedSample: BiomarkerSnapshot.Sample? {
        guard let selectedDate else { return nil }
        return chartSamples.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private func selectionCallout(for sample: BiomarkerSnapshot.Sample) -> some View {
        VStack(spacing: Spacing.xxs) {
            Text(calloutValue(for: sample))
                .font(AppFont.scaled(13, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
            Text(dayLabel(for: sample.date))
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .glassSurface(cornerRadius: Spacing.chipCornerRadius)
    }

    /// The scrubbed reading; for blood pressure, both halves of that day.
    private func calloutValue(for sample: BiomarkerSnapshot.Sample) -> String {
        if let diastolic = snapshot.secondarySamples.first(where: { $0.date == sample.date }) {
            return BiomarkerSeriesService.bloodPressureText(systolic: sample.value, diastolic: diastolic.value) + " mmHg"
        }
        return formattedWithUnit(biomarker.displayValue(sample.value, for: unit))
    }

    /// A display-unit value with its unit, e.g. "72.0 kg".
    private func formattedWithUnit(_ displayValue: Double) -> String {
        BiomarkerSeriesService.formatValue(displayValue, for: biomarker)
            + (biomarker.displayUnit(for: unit).map { " \($0)" } ?? "")
    }

    @ChartContentBuilder
    private func trendMarks(for sample: BiomarkerSnapshot.Sample, floor: Double) -> some ChartContent {
        // Sample values are canonical metric — convert so the chart's
        // Y axis matches the imperial hero number above it.
        let displayValue = biomarker.displayValue(sample.value, for: unit)
        LineMark(
            x: .value("Date", sample.date, unit: .day),
            y: .value(biomarker.displayName, displayValue),
            series: .value("Reading", "primary")
        )
        .interpolationMethod(.monotone)
        .lineStyle(.init(lineWidth: 2, lineCap: .round, lineJoin: .round))
        .foregroundStyle(AppColor.accentPrimary)
        .accessibilityLabel(dayLabel(for: sample.date))
        .accessibilityValue(calloutValue(for: sample))

        // Filled down to the axis floor, not to zero, which now sits
        // outside the plot. Blood pressure skips it: the band would
        // swallow the diastolic line drawn below.
        if snapshot.secondarySamples.isEmpty {
            areaMark(for: sample, displayValue: displayValue, floor: floor)
        }
    }

    /// The diastolic line under blood pressure's systolic one, in a
    /// lighter ink. VoiceOver already hears both on the systolic mark.
    private func diastolicMark(for sample: BiomarkerSnapshot.Sample) -> some ChartContent {
        LineMark(
            x: .value("Date", sample.date, unit: .day),
            y: .value(biomarker.displayName, sample.value),
            series: .value("Reading", "diastolic")
        )
        .interpolationMethod(.monotone)
        .lineStyle(.init(lineWidth: 2, lineCap: .round, lineJoin: .round))
        .foregroundStyle(AppColor.accentLight)
        .accessibilityHidden(true)
    }

    private func areaMark(for sample: BiomarkerSnapshot.Sample, displayValue: Double, floor: Double) -> some ChartContent {
        AreaMark(
            x: .value("Date", sample.date, unit: .day),
            yStart: .value(biomarker.displayName, floor),
            yEnd: .value(biomarker.displayName, displayValue)
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
        // Same reading as the line — VoiceOver would announce it twice.
        .accessibilityHidden(true)
    }

    /// "Today", "Yesterday", else the calendar date ("12 Mar"), so ticks
    /// read in the user's locale rather than as English abbreviations.
    private func dayLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return String(localized: "Today") }
        if Calendar.current.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// Ticks wide enough that dated labels ("12 Mar") don't collide at
    /// each range.
    private var axisStride: Int {
        switch range {
        case .week:    return 2
        case .month:   return 7
        case .quarter: return 21
        }
    }

    /// Under the chart: how many days actually had a reading, and the
    /// dashed line's value, so a gappy series isn't mistaken for a full one.
    private var chartCaption: some View {
        HStack(spacing: Spacing.sm) {
            if let chartMean {
                HStack(spacing: Spacing.xs) {
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle().fill(AppColor.textTertiary).frame(width: 3, height: 1)
                        }
                    }
                    .accessibilityHidden(true)
                    Text("Average \(formattedWithUnit(chartMean))")
                }
            }
            Spacer(minLength: 0)
            Text("^[\(chartSamples.count) day](inflect: true) with a reading")
        }
        .font(AppFont.caption2)
        .foregroundStyle(AppColor.textSecondary)
        .monospacedDigit()
    }

    private var emptyRangePlaceholder: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(AppFont.scaled(16, weight: .light))
                .foregroundStyle(AppColor.textTertiary)
            Text("Not enough readings in this range. Try a longer one.")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
        }
        .padding(Spacing.md)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    private var insufficientChartPlaceholder: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "hourglass")
                .font(AppFont.scaled(16, weight: .light))
                .foregroundStyle(AppColor.textTertiary)
            Text("Need at least 4 days of data to chart a trend.")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
        }
        .padding(Spacing.md)
        // Same card as the chart it stands in for.
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    // MARK: - Delta block

    private var deltaBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Vs recent average")
                .textCase(.uppercase)
                .font(AppFont.eyebrow)
                .tracking(1.0)
                .foregroundStyle(AppColor.textSecondary)
                .accessibilityAddTraits(.isHeader)
            Text(deltaLine)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    /// Enough readings for an average to mean something. Below it the
    /// chart placeholder already says more data is needed, so the
    /// comparison card stays out rather than saying it a second time.
    private var hasComparison: Bool {
        // A systolic-only average would misread as the whole blood
        // pressure, so that card stays out.
        snapshot.latest != nil && snapshot.secondarySamples.isEmpty
            && snapshot.sparkline.count >= Self.minimumSamples
    }

    private static let minimumSamples = 4

    private var deltaLine: String {
        guard let latest = snapshot.latest, hasComparison else { return "" }
        let avg = snapshot.sparkline.reduce(0, +) / Double(snapshot.sparkline.count)
        // Convert both endpoints to the display unit *before* subtracting so
        // the temperature offset (°C→°F adds 32) cancels — the delta is a
        // true difference, not an inflated one.
        let delta = biomarker.displayValue(latest, for: unit) - biomarker.displayValue(avg, for: unit)
        if abs(delta) < 0.01 {
            return String(localized: "Right at your recent average.")
        }
        let amount = formattedWithUnit(abs(delta))
        return delta > 0
            ? String(localized: "\(amount) above your recent average.")
            : String(localized: "\(amount) below your recent average.")
    }

    // MARK: - Footnote

    private var footnote: some View {
        Text(footnoteText)
            .font(AppFont.scaled(11))
            .foregroundStyle(AppColor.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private var footnoteText: String {
        switch biomarker {
        case .hrvBaseline, .rhrBaseline, .sleepBaseline, .stepsBaseline:
            return String(localized: "Source: Apple Health")
        case .weight:
            return String(localized: "Source: your weight log")
        case .bodyFat, .waist, .bloodPressure, .bodyTemperature:
            return String(localized: "Source: Apple Health, including readings you log here")
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
            samples: [50, 52, 54, 53, 55, 57, 56, 58, 60, 58, 59, 58, 60, 62].enumerated().map {
                BiomarkerSnapshot.Sample(
                    date: Calendar.current.date(byAdding: .day, value: $0.offset - 13, to: .now) ?? .now,
                    value: Double($0.element)
                )
            },
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
