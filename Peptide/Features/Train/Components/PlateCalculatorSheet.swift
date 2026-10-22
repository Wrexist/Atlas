import SwiftUI

/// Bar-loading helper: type a target, see which plates go on each side.
/// All figures are in the unit picked at the top, which opens on the
/// user's own measurement unit. Plates and bar weights are the user's own
/// from Training settings — the maths lives in `PlateCalculatorEngine`.
struct PlateCalculatorSheet: View {
    /// Pre-fills the target, in the user's display unit. Nil opens on the
    /// empty bar.
    var initialTarget: Double?
    /// The bar the exercise is loaded on; the sheet opens on its weight.
    var bar: BarKind = .olympic

    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    @State private var unit: MeasurementUnit = .metric
    @State private var selectedBar: BarKind = .olympic
    /// The fields edit text drafts so the loadout follows every keystroke;
    /// a value-bound TextField only commits on focus loss.
    @State private var targetText = ""
    @State private var barText = ""
    @State private var hasSeeded = false
    @FocusState private var focusedField: Field?

    private enum Field { case target, bar }

    private var preferences: TrainingPreferences {
        dataStore.profile.trainingPreferences ?? TrainingPreferences()
    }

    private var plates: [Double] { preferences.plates(for: unit) }
    private var target: Double { Self.parse(targetText) }
    private var barWeight: Double { Self.parse(barText) }

    private var outcome: PlateCalculatorEngine.Outcome {
        PlateCalculatorEngine.calculate(target: target, barWeight: barWeight, plates: plates)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    unitPicker
                    inputs
                    result
                }
                .padding(Spacing.screenPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("Plate calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .fontWeight(.semibold)
                }
            }
        }
        .liquidGlassPresentation(detents: [.medium, .large])
        .onAppear(perform: seed)
    }

    // MARK: - Inputs

    private var unitPicker: some View {
        Picker("Unit", selection: Binding(get: { unit }, set: { switchUnit(to: $0) })) {
            Text("kg").tag(MeasurementUnit.metric)
            Text("lb").tag(MeasurementUnit.imperial)
        }
        .pickerStyle(.segmented)
    }

    private var inputs: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                weightField("Target", text: $targetText, field: .target)
                Divider().background(AppColor.glassBorder)
                barPicker
                weightField("Bar", text: $barText, field: .bar)
            }
        }
    }

    private var barPicker: some View {
        HStack(spacing: Spacing.sm) {
            Text("Bar type")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Spacer(minLength: 0)
            Picker("Bar type", selection: Binding(get: { selectedBar }, set: { selectBar($0) })) {
                ForEach(BarKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private func weightField(_ label: LocalizedStringKey, text: Binding<String>, field: Field) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(label)
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Spacer(minLength: 0)
            TextField(label, text: text)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: field)
                .multilineTextAlignment(.trailing)
                .font(AppFont.scaled(24, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.accentLight)
                .monospacedDigit()
                .frame(maxWidth: 140)
                .minimumHitArea()
            Text(unit.weightSuffix)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    // MARK: - Result

    @ViewBuilder
    private var result: some View {
        switch outcome {
        case .loaded(let loadout):
            loadoutCard(loadout)
        case .belowBar:
            message("The bar alone weighs \(label(barWeight)). Enter a heavier target.")
        case .invalid:
            message("Enter a target above zero.")
        }
    }

    private func loadoutCard(_ loadout: PlateCalculatorEngine.Loadout) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Each side")
                    .font(AppFont.eyebrow)
                    .tracking(1.2)
                    .foregroundStyle(AppColor.textSecondary)
                BarLoadDiagram(platesPerSide: loadout.platesPerSide, unit: unit)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spokenSummary(loadout))
                breakdown(loadout)
                if !loadout.isExact {
                    Text(inexactNote(loadout))
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func inexactNote(_ loadout: PlateCalculatorEngine.Loadout) -> String {
        let total = label(loadout.loadedTotal)
        let gap = label(abs(loadout.remainder))
        return loadout.remainder > 0
            ? String(localized: "Closest loadable is \(total), \(gap) short of your target.")
            : String(localized: "Closest loadable is \(total), \(gap) over your target.")
    }

    private func breakdown(_ loadout: PlateCalculatorEngine.Loadout) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if loadout.perSide.isEmpty {
                Text("Empty bar")
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textPrimary)
            }
            ForEach(loadout.perSide, id: \.weight) { entry in
                HStack(spacing: Spacing.sm) {
                    Circle()
                        .fill(plateColor(entry.weight))
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(label(entry.weight))
                        .font(AppFont.callout.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer(minLength: 0)
                    Text("× \(entry.count)")
                        .font(AppFont.callout)
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(AppFont.callout)
            .foregroundStyle(AppColor.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(Spacing.md)
    }

    // MARK: - Helpers

    /// Carries the target across units (100 kg becomes 220.5 lb, not
    /// 100 lb) and swaps in that unit's standard bar.
    private func switchUnit(to newUnit: MeasurementUnit) {
        guard newUnit != unit else { return }
        let targetKg = unit.kilograms(fromDisplayed: target)
        unit = newUnit
        targetText = Self.format((newUnit.weightForDisplay(targetKg) * 10).rounded() / 10)
        barText = Self.format(preferences.barWeight(selectedBar, unit: newUnit))
    }

    private func selectBar(_ newBar: BarKind) {
        selectedBar = newBar
        barText = Self.format(preferences.barWeight(newBar, unit: unit))
    }

    private func seed() {
        guard !hasSeeded else { return }
        hasSeeded = true
        let profileUnit = dataStore.profile.bodyMetrics.unit
        unit = profileUnit
        selectedBar = bar
        let barWeight = preferences.barWeight(bar, unit: profileUnit)
        barText = Self.format(barWeight)
        targetText = Self.format(initialTarget ?? barWeight)
    }

    /// Tries "." first so a pasted "62.5" isn't read as 625 where "." is
    /// the grouping separator, then the locale's own decimal separator.
    private static func parse(_ text: String) -> Double {
        Double(text) ?? (try? Double(text, format: FloatingPointFormatStyle<Double>())) ?? 0
    }

    private static func format(_ weight: Double) -> String {
        weight.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    private func plateColor(_ plate: Double) -> Color {
        PlateCalculatorEngine.tone(forPlate: plate, unit: unit).color
    }

    private func label(_ weight: Double) -> String {
        "\(weight.formatted(.number.precision(.fractionLength(0...2)))) \(unit.weightSuffix)"
    }

    private func spokenSummary(_ loadout: PlateCalculatorEngine.Loadout) -> String {
        guard !loadout.perSide.isEmpty else { return String(localized: "Empty bar") }
        let parts = loadout.perSide.map { "\($0.count) × \(label($0.weight))" }
        return String(localized: "Each side: \(parts.joined(separator: ", "))")
    }
}
