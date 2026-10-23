import SwiftUI

/// Review step of a lab-report scan. Every transcribed row is shown with
/// what the report printed, the catalog marker it matched, and the value
/// in that marker's unit. Nothing is saved until the user taps Save, and
/// only the rows they leave ticked.
///
/// A row whose name didn't match starts skipped; the user can match it by
/// hand from the marker picker. A row whose unit Atlas can't convert keeps
/// an empty value field rather than guessing — the user types the number
/// in the catalog unit.
struct LabScanReviewView: View {
    let sex: BiologicalSex
    let onSave: ([LabValue]) -> Void

    @State private var rows: [LabReportEngine.Row]
    /// Typed text per row, kept apart from `rows` so "5." isn't reformatted
    /// to "5" mid-edit.
    @State private var valueTexts: [UUID: String]
    @State private var reportDate: Date
    @State private var source: String

    init(scan: LabReportEngine.Scan, sex: BiologicalSex, onSave: @escaping ([LabValue]) -> Void) {
        self.sex = sex
        self.onSave = onSave
        let rows = LabReportEngine.rows(from: scan)
        _rows = State(initialValue: rows)
        _valueTexts = State(initialValue: Dictionary(
            uniqueKeysWithValues: rows.map { ($0.id, $0.value.map(LabValueFormat.string) ?? "") }
        ))
        _reportDate = State(initialValue: LabReportEngine.date(from: scan.collectedOn, notAfter: Date()) ?? Date())
        _source = State(initialValue: scan.labName ?? "")
    }

    private static let decimalParser: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = .current
        return f
    }()

    private func parsedValue(for row: LabReportEngine.Row) -> Double? {
        let text = (valueTexts[row.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let value = Self.decimalParser.number(from: text)?.doubleValue ?? Double(text)
        return value.flatMap { $0 >= 0 && $0.isFinite ? $0 : nil }
    }

    /// The entries Save would write, in report order.
    private var confirmedValues: [LabValue] {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows.compactMap { row in
            guard row.isIncluded, let panel = row.panel, let value = parsedValue(for: row) else { return nil }
            return LabValue(
                date: row.date ?? reportDate,
                panel: panel,
                value: value,
                source: trimmedSource.isEmpty ? nil : trimmedSource
            )
        }
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Drawn on", selection: $reportDate, in: ...Date(), displayedComponents: .date)
                TextField("Lab / source (optional)", text: $source)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("Report")
            } footer: {
                Text("Check the date — it's read from the report and applies to every result below.")
            }

            Section {
                ForEach($rows) { $row in
                    rowView($row)
                }
            } header: {
                Text("^[\(rows.count) result](inflect: true) found")
            } footer: {
                Text("Values are converted to the unit Atlas charts. Compare each one with your report before saving.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .glassFormStyle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save \(confirmedValues.count)") {
                    Haptics.success()
                    onSave(confirmedValues)
                }
                .disabled(confirmedValues.isEmpty)
            }
        }
    }

    private func rowView(_ row: Binding<LabReportEngine.Row>) -> some View {
        let current = row.wrappedValue
        let value = parsedValue(for: current)
        let canInclude = current.panel != nil && value != nil
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Button {
                    Haptics.selection()
                    row.wrappedValue.isIncluded.toggle()
                } label: {
                    Image(systemName: current.isIncluded && canInclude ? "checkmark.circle.fill" : "circle")
                        .font(AppFont.scaled(20))
                        .foregroundStyle(current.isIncluded && canInclude ? AppColor.accentPrimary : AppColor.textTertiary)
                }
                .buttonStyle(.plain)
                .minimumHitArea()
                .disabled(!canInclude)
                .accessibilityLabel(current.isIncluded ? "Included" : "Skipped")
                .accessibilityHint("Toggles whether this result is saved.")

                printed(current.marker)
            }

            Picker("Marker", selection: panelBinding(row)) {
                Text("Not matched — skip").tag(LabPanel?.none)
                // Grouped like the manual editor's picker, so a long
                // catalog reads as a few short lists.
                ForEach(LabPanel.Category.allCases) { category in
                    Section(category.displayName) {
                        ForEach(LabPanel.allCases.filter { $0.category == category && $0 != .other }) { panel in
                            Text(panel.displayName).tag(Optional(panel))
                        }
                    }
                }
            }
            .pickerStyle(.menu)

            if let panel = current.panel {
                HStack {
                    TextField("Value", text: valueTextBinding(current.id))
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                    Text(panel.canonicalUnit)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
                if let note = warning(for: current, panel: panel, value: value) {
                    Label(note, systemImage: "exclamationmark.triangle.fill")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.warning)
                }
            }

            if let date = current.date {
                Text("Drawn \(date.formatted(date: .abbreviated, time: .omitted))")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    /// What the report printed: name, value and unit, and its range.
    private func printed(_ marker: LabReportEngine.Marker) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(marker.name)
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text(printedValue(marker))
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func printedValue(_ marker: LabReportEngine.Marker) -> String {
        let value = marker.value.map { "\(LabValueFormat.string($0)) \(marker.unit)" }
            ?? String(localized: "No numeric value")
        guard let range = marker.referenceText?.nilIfEmpty else {
            return String(localized: "Report: \(value)")
        }
        return String(localized: "Report: \(value) · ref. \(range)")
    }

    private func warning(for row: LabReportEngine.Row, panel: LabPanel, value: Double?) -> String? {
        if row.value == nil, (valueTexts[row.id] ?? "").isEmpty {
            let unit = row.marker.unit.nilIfEmpty ?? String(localized: "no unit")
            return String(localized: "Atlas can't convert \(unit). Enter the value in \(panel.canonicalUnit).")
        }
        if let value, LabReportEngine.looksLikeUnitSlip(value, panel: panel, sex: sex) {
            return String(localized: "Far outside the usual range for \(panel.canonicalUnit). Check the unit.")
        }
        return nil
    }

    /// Re-matching a row re-converts its printed value into the new
    /// marker's unit, and ticks it when that worked.
    private func panelBinding(_ row: Binding<LabReportEngine.Row>) -> Binding<LabPanel?> {
        Binding(
            get: { row.wrappedValue.panel },
            set: { panel in
                let converted = panel.flatMap { LabReportEngine.convertedValue(row.wrappedValue.marker, to: $0) }
                row.wrappedValue.panel = panel
                row.wrappedValue.value = converted
                row.wrappedValue.isIncluded = converted != nil
                valueTexts[row.wrappedValue.id] = converted.map(LabValueFormat.string) ?? ""
            }
        )
    }

    private func valueTextBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { valueTexts[id] ?? "" },
            set: { valueTexts[id] = $0 }
        )
    }
}
