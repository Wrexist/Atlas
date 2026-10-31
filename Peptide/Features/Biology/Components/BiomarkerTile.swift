import SwiftUI

/// One biomarker card on the Biology tab: a soft wash of the metric's
/// colour over glass, the reading large and light with its unit small
/// beside it, a thin trend line, and the average underneath. Three
/// sizes, picked from the card's menu: small sits two to a row, medium
/// and large take the full width with a longer and a taller line.
///
/// Tapping opens `BiomarkerDetailSheet`. A card with no reading says
/// how to get one instead of showing a dash.
struct BiomarkerTile: View {
    let snapshot: BiomarkerSnapshot
    let size: BiomarkerTileSize
    let unit: MeasurementUnit
    var onTap: () -> Void
    var onResize: (BiomarkerTileSize) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var biomarker: Biomarker { snapshot.biomarker }
    private var tint: Color { biomarker.tint }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                header
                if snapshot.latest == nil {
                    emptyBody
                } else if size == .small {
                    reading
                    Spacer(minLength: 0)
                    sparkline(height: 28)
                    footer
                } else {
                    HStack(alignment: .bottom, spacing: Spacing.md) {
                        reading
                        Spacer(minLength: Spacing.sm)
                        if size == .medium, !dynamicTypeSize.isAccessibilitySize {
                            sparkline(height: 40).frame(maxWidth: 160)
                        }
                    }
                    if size == .large {
                        sparkline(height: 96)
                    }
                    footer
                }
            }
            .frame(maxWidth: .infinity, minHeight: size == .small ? 148 : nil, alignment: .topLeading)
            .padding(Spacing.md)
            .background { wash }
            .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the chart")
        .contextMenu { sizeMenu }
    }

    // MARK: - Parts

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: biomarker.icon)
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(biomarker.displayName)
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            if let arrow = trendArrow {
                Image(systemName: arrow)
                    .font(AppFont.scaled(11, weight: .bold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
        }
    }

    private var reading: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
            Text(valueText)
                .font(AppFont.scaled(size == .small ? 32 : 40, weight: .light, relativeTo: .largeTitle))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            if let unitText = biomarker.displayUnit(for: unit) {
                Text(unitText)
                    .font(AppFont.scaled(13, weight: .medium))
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func sparkline(height: CGFloat) -> some View {
        if snapshot.samples.count >= 2 {
            BiomarkerSparkline(samples: snapshot.samples, tint: tint, height: height)
                .frame(height: height)
                .accessibilityHidden(true)
        }
    }

    private var footer: some View {
        Text(footerText)
            .font(AppFont.scaled(11, weight: .medium))
            .foregroundStyle(AppColor.textSecondary)
            .lineLimit(2)
    }

    private var emptyBody: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Spacer(minLength: 0)
            Text("No data yet")
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
            Text(emptyHint)
                .font(AppFont.scaled(11))
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The metric's colour, strongest in the top corner and fading out,
    /// under the glass so light and dark mode each get their own depth.
    private var wash: some View {
        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [tint.opacity(0.26), tint.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    @ViewBuilder
    private var sizeMenu: some View {
        Picker("Card size", selection: Binding(get: { size }, set: onResize)) {
            Label("Small", systemImage: "square.grid.2x2").tag(BiomarkerTileSize.small)
            Label("Medium", systemImage: "rectangle").tag(BiomarkerTileSize.medium)
            Label("Large", systemImage: "rectangle.expand.vertical").tag(BiomarkerTileSize.large)
        }
    }

    // MARK: - Text

    private var emptyHint: LocalizedStringKey {
        if biomarker == .latestLabPanel { return "Add results in Labs" }
        return biomarker.supportsManualEntry ? "Tap to log a reading" : "Connect Apple Health to fill this in"
    }

    private var valueText: String {
        guard let latest = snapshot.latest else { return "—" }
        if let diastolic = snapshot.latestSecondary {
            return BiomarkerSeriesService.bloodPressureText(systolic: latest, diastolic: diastolic)
        }
        return BiomarkerSeriesService.formatValue(biomarker.displayValue(latest, for: unit), for: biomarker)
    }

    /// "Avg 58 ms · Steady", or the stale note once the reading is old.
    private var footerText: String {
        let verb = snapshot.changeText.components(separatedBy: " · ").first ?? ""
        var parts: [String] = []
        if snapshot.samples.count >= 2, snapshot.latestSecondary == nil {
            let mean = snapshot.sparkline.reduce(0, +) / Double(snapshot.sparkline.count)
            let formatted = BiomarkerSeriesService.formatValue(biomarker.displayValue(mean, for: unit), for: biomarker)
            let withUnit = biomarker.displayUnit(for: unit).map { "\(formatted) \($0)" } ?? formatted
            parts.append(String(localized: "Avg \(withUnit)"))
        }
        if let stale = snapshot.staleNote() {
            parts.append(stale)
        } else if !verb.isEmpty {
            parts.append(verb)
        }
        return parts.joined(separator: " · ")
    }

    private var trendArrow: String? {
        switch snapshot.trend {
        case .up:   "arrow.up.right"
        case .down: "arrow.down.right"
        case .flat, .insufficient: nil
        }
    }
}

extension Biomarker {
    /// The metric family's colour, shared by its card wash, icon and line.
    var tint: Color {
        switch self {
        case .weight:           AppColor.macroProtein
        case .hrvBaseline:      AppColor.metricHRV
        case .rhrBaseline:      AppColor.metricHeartRate
        case .sleepBaseline:    AppColor.metricSleep
        case .stepsBaseline:    AppColor.metricActivity
        case .bodyTemperature:  AppColor.textSecondary
        case .bodyFat:          AppColor.streak
        case .waist:            AppColor.accentLight
        case .bloodPressure:    AppColor.metricHeartRate
        case .latestLabPanel:   AppColor.accentPrimary
        }
    }
}
