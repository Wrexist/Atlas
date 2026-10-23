import SwiftUI

/// "20 kg bar + 25 + 10 per side" under a plate-loaded exercise's sets,
/// for the set about to be lifted: a small drawing of the loaded bar and
/// the plates to slide on. Tapping opens the full plate calculator.
struct PlateLoadStrip: View {
    let weightKg: Double
    let unit: MeasurementUnit
    let bar: BarKind

    @Environment(DataStore.self) private var dataStore
    @State private var showingCalculator = false

    private var preferences: TrainingPreferences {
        dataStore.profile.trainingPreferences ?? TrainingPreferences()
    }

    private var barWeight: Double { preferences.barWeight(bar, unit: unit) }

    /// The set's weight in the display unit, to the hundredth the engine
    /// works in — 100 kg shown in pounds is 220.46, not 220.4622…
    private var target: Double { (unit.weightForDisplay(weightKg) * 100).rounded() / 100 }

    private var outcome: PlateCalculatorEngine.Outcome {
        PlateCalculatorEngine.calculate(target: target, barWeight: barWeight, plates: preferences.plates(for: unit))
    }

    var body: some View {
        Button {
            Haptics.selection()
            showingCalculator = true
        } label: {
            HStack(spacing: Spacing.sm) {
                BarLoadDiagram(platesPerSide: platesPerSide, unit: unit, plateWidth: 4, maxPlateHeight: 24, barLength: 18)
                Text(summary)
                    .font(AppFont.caption2.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .frame(minHeight: Spacing.minimumHitTarget)
            .background(
                AppColor.trainingInput,
                in: RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
            )
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel(Text(summary))
        .accessibilityHint(Text("Opens the plate calculator"))
        .sheet(isPresented: $showingCalculator) {
            PlateCalculatorSheet(initialTarget: target > 0 ? target : nil, bar: bar)
        }
    }

    private var platesPerSide: [Double] {
        if case .loaded(let loadout) = outcome { return loadout.platesPerSide }
        return []
    }

    private var summary: String {
        let barLabel = label(barWeight)
        switch outcome {
        case .loaded(let loadout):
            guard !loadout.perSide.isEmpty else { return String(localized: "Empty \(barLabel) bar") }
            let plates = loadout.perSide.map { entry in
                entry.count > 1 ? "\(entry.count) × \(number(entry.weight))" : number(entry.weight)
            }.joined(separator: " + ")
            let line = String(localized: "\(barLabel) bar + \(plates) per side")
            guard !loadout.isExact else { return line }
            return String(localized: "\(line) · \(label(loadout.loadedTotal)) on the bar")
        case .belowBar:
            return String(localized: "Lighter than the \(barLabel) bar")
        case .invalid:
            return String(localized: "\(barLabel) bar · enter a weight for plates")
        }
    }

    private func number(_ weight: Double) -> String {
        weight.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func label(_ weight: Double) -> String {
        "\(number(weight)) \(unit.weightSuffix)"
    }
}

/// A bar seen side-on with its plates mirrored on each sleeve, heaviest
/// against the collar. Plate height follows its weight (a 25 kg / 55 lb
/// plate is full height) and colour follows the competition bands.
struct BarLoadDiagram: View {
    let platesPerSide: [Double]
    let unit: MeasurementUnit
    var plateWidth: CGFloat = 12
    var maxPlateHeight: CGFloat = 112
    var barLength: CGFloat = 56
    /// Past this many plates a side the stack would run off a phone
    /// screen, so the rest collapse into a "+n" badge.
    var maxDrawnPlates = 8

    var body: some View {
        let drawn = Array(platesPerSide.prefix(maxDrawnPlates))
        let overflow = platesPerSide.count - drawn.count
        HStack(spacing: max(1, plateWidth / 6)) {
            if overflow > 0 { overflowBadge(overflow) }
            ForEach(Array(drawn.reversed().enumerated()), id: \.offset) { _, plate in
                plateView(plate)
            }
            Capsule()
                .fill(AppColor.textTertiary)
                .frame(width: barLength, height: max(2, maxPlateHeight / 11))
            ForEach(Array(drawn.enumerated()), id: \.offset) { _, plate in
                plateView(plate)
            }
            if overflow > 0 { overflowBadge(overflow) }
        }
        .frame(height: maxPlateHeight)
    }

    private func plateView(_ plate: Double) -> some View {
        let fullHeightKg = 25.0
        let share = min(1, unit.kilograms(fromDisplayed: plate) / fullHeightKg)
        return RoundedRectangle(cornerRadius: max(1, plateWidth / 4), style: .continuous)
            .fill(PlateCalculatorEngine.tone(forPlate: plate, unit: unit).color)
            .frame(width: plateWidth, height: maxPlateHeight * (0.32 + 0.68 * share))
    }

    private func overflowBadge(_ count: Int) -> some View {
        Text("+\(count)")
            .font(AppFont.caption2.weight(.semibold))
            .foregroundStyle(AppColor.textSecondary)
    }
}

extension PlateCalculatorEngine.Tone {
    var color: Color {
        switch self {
        case .red:    return AppColor.plateRed
        case .blue:   return AppColor.plateBlue
        case .yellow: return AppColor.plateYellow
        case .green:  return AppColor.plateGreen
        case .white:  return AppColor.plateWhite
        case .grey:   return AppColor.plateGrey
        }
    }
}
