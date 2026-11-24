import SwiftUI

/// One biomarker card on the Biology tab: a glass card in the app's one
/// accent, the reading large and light with its unit small beside it, a
/// thin trend line, and the average underneath. Three
/// sizes, picked from the card's menu: small sits two to a row, medium
/// and large take the full width with a longer and a taller line.
///
/// Tapping opens `BiomarkerDetailSheet`. A card with no reading says
/// how to get one instead of showing a dash.
struct BiomarkerTile: View {
    let snapshot: BiomarkerSnapshot
    let size: BiomarkerTileSize
    let unit: MeasurementUnit
    /// Whether this device reads Apple Health, so an empty card asks
    /// for the step still missing rather than one already taken.
    let healthConnected: Bool
    var onTap: () -> Void
    var onResize: (BiomarkerTileSize) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var biomarker: Biomarker { snapshot.biomarker }
    /// One accent for every card: a hue per metric put a palette beside
    /// the page's single accent without telling the metrics apart any
    /// better than their names do.
    private var tint: Color { AppColor.accentPrimary }

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
            .frame(maxWidth: .infinity, minHeight: size == .small ? 148 : nil, maxHeight: .infinity, alignment: .topLeading)
            .padding(Spacing.md)
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
            Text(biomarker.shortName)
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel(Text(biomarker.displayName))
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
            if let unitText = biomarker.displayUnit(for: unit) ?? snapshot.unitLabel {
                Text(unitText)
                    .font(AppFont.scaled(13, weight: .medium))
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize()
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
            // Small cards pair up: both footers keep two lines so the two
            // trend lines above them sit on one level.
            .lineLimit(2, reservesSpace: size == .small)
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
        switch biomarker {
        case .latestLabPanel:
            return "Add results in Labs"
        case .weight:
            return "Log a weigh-in to fill this in"
        case .bodyFat, .waist, .bloodPressure, .bodyTemperature:
            return "Tap to log a reading"
        case .hrvBaseline, .rhrBaseline, .sleepBaseline, .stepsBaseline:
            guard healthConnected else { return "Connect Apple Health to fill this in" }
            return biomarker == .stepsBaseline
                ? "Carry your iPhone or wear Apple Watch to record this"
                : "Wear Apple Watch to record this"
        }
    }

    private var valueText: String {
        guard let latest = snapshot.latest else { return "—" }
        if let diastolic = snapshot.latestSecondary {
            return BiomarkerSeriesService.bloodPressureText(systolic: latest, diastolic: diastolic)
        }
        return BiomarkerSeriesService.formatValue(biomarker.displayValue(latest, for: unit), for: biomarker)
    }

    /// "Avg 58 ms · Steady", or the stale note once the reading is old.
    /// A lab reading always leads with its panel name, so the number
    /// never stands alone.
    private var footerText: String {
        if let context = snapshot.contextLabel {
            return [context, snapshot.staleNote()].compactMap { $0 }.joined(separator: " · ")
        }
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

/// A wearable biomarker with no reading yet: the card's header over a
/// dash, all in tertiary ink, so it reads as a slot waiting to fill
/// rather than a card with something to say.
struct AwaitingBiomarkerTile: View {
    let biomarker: Biomarker
    let caption: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: biomarker.icon)
                        .font(AppFont.scaled(11, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(biomarker.shortName)
                        .font(AppFont.scaled(13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityLabel(Text(biomarker.displayName))
                }
                .foregroundStyle(AppColor.textSecondary)
                Text(verbatim: "—")
                    .font(AppFont.scaled(24, weight: .light, relativeTo: .title2))
                    .foregroundStyle(AppColor.textTertiary)
                    .accessibilityHidden(true)
                Text(caption)
                    .font(AppFont.scaled(11, weight: .medium))
                    .foregroundStyle(AppColor.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .glassSurface(cornerRadius: Spacing.cardCornerRadius)
            .opacity(0.75)
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the chart")
    }
}
