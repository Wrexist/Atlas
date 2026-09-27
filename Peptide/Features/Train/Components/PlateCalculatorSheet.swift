import SwiftUI

/// Bar-loading helper: type a target, see which plates go on each side.
/// All figures are in the unit picked at the top, which opens on the
/// user's own measurement unit — the maths lives in `PlateCalculatorEngine`.
struct PlateCalculatorSheet: View {
    /// Pre-fills the target, in the user's display unit. Nil opens on the
    /// empty bar.
    var initialTarget: Double?

    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    @State private var unit: MeasurementUnit = .metric
    @State private var target: Double = 0
    @State private var barWeight: Double = 0
    @State private var hasSeeded = false

    /// Plates drawn per side before the diagram collapses the rest into a
    /// "+n" badge — past this the stack would run off a phone screen.
    private static let maxDrawnPlates = 8

    private var plates: [Double] { PlateCalculatorEngine.defaultPlates(for: unit) }

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
            }
        }
        .liquidGlassPresentation(detents: [.medium, .large])
        .onAppear(perform: seed)
        .onChange(of: unit) { _, newUnit in
            barWeight = PlateCalculatorEngine.defaultBarWeight(for: newUnit)
        }
    }

    // MARK: - Inputs

    private var unitPicker: some View {
        Picker("Unit", selection: $unit) {
            Text("kg").tag(MeasurementUnit.metric)
            Text("lb").tag(MeasurementUnit.imperial)
        }
        .pickerStyle(.segmented)
    }

    private var inputs: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                weightField("Target", value: $target)
                Divider().background(AppColor.glassBorder)
                weightField("Bar", value: $barWeight)
            }
        }
    }

    private func weightField(_ label: LocalizedStringKey, value: Binding<Double>) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(label)
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Spacer(minLength: 0)
            TextField(label, value: value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
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
            message("Enter a target and a bar weight above zero.")
        }
    }

    private func loadoutCard(_ loadout: PlateCalculatorEngine.Loadout) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Each side")
                    .font(AppFont.eyebrow)
                    .tracking(1.2)
                    .foregroundStyle(AppColor.textSecondary)
                barDiagram(loadout.platesPerSide)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spokenSummary(loadout))
                breakdown(loadout)
                if !loadout.isExact {
                    Text("Closest loadable is \(label(loadout.loadedTotal)), \(label(loadout.remainder)) short of your target.")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Mirrored stack: plates inner-to-outer on each sleeve, heaviest
    /// against the collar, bar in the middle.
    private func barDiagram(_ perSide: [Double]) -> some View {
        let drawn = Array(perSide.prefix(Self.maxDrawnPlates))
        let overflow = perSide.count - drawn.count
        return HStack(spacing: Spacing.xxs) {
            if overflow > 0 { overflowBadge(overflow) }
            ForEach(Array(drawn.reversed().enumerated()), id: \.offset) { _, plate in
                plateView(plate)
            }
            RoundedRectangle(cornerRadius: Spacing.xxs, style: .continuous)
                .fill(AppColor.textTertiary)
                .frame(width: 56, height: 10)
            ForEach(Array(drawn.enumerated()), id: \.offset) { _, plate in
                plateView(plate)
            }
            if overflow > 0 { overflowBadge(overflow) }
        }
        .frame(height: 112)
    }

    private func plateView(_ plate: Double) -> some View {
        let heaviest = plates.first ?? plate
        let height = 36 + 76 * CGFloat(min(1, plate / heaviest))
        return RoundedRectangle(cornerRadius: Spacing.xxs, style: .continuous)
            .fill(plateColor(plate))
            .frame(width: 12, height: height)
    }

    private func overflowBadge(_ count: Int) -> some View {
        Text("+\(count)")
            .font(AppFont.caption.weight(.semibold))
            .foregroundStyle(AppColor.textSecondary)
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

    private func seed() {
        guard !hasSeeded else { return }
        hasSeeded = true
        let profileUnit = dataStore.profile.bodyMetrics.unit
        unit = profileUnit
        barWeight = PlateCalculatorEngine.defaultBarWeight(for: profileUnit)
        target = initialTarget ?? barWeight
    }

    /// Colour by size rank, heaviest first — red, blue, yellow, green on a
    /// kilo set, matching competition plates.
    private func plateColor(_ plate: Double) -> Color {
        let palette = [
            AppColor.destructive, AppColor.macroWater, AppColor.warning,
            AppColor.success, AppColor.textSecondary, AppColor.textTertiary
        ]
        let rank = plates.firstIndex(of: plate) ?? palette.count - 1
        return palette[min(rank, palette.count - 1)]
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
