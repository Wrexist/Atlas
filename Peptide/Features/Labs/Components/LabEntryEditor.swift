import SwiftUI

/// Log-or-edit sheet for a single `LabValue`. Three inputs (panel,
/// value, date) plus two optional fields (source, note). The
/// panel picker is the most consequential interaction — users
/// don't always know "is total or free testosterone the one I
/// want?" — so the picker exposes each panel's canonical unit and
/// category as supporting context.
struct LabEntryEditor: View {
    let initial: LabValue?
    let onSave: (LabValue) -> Void
    let onDelete: ((UUID) -> Void)?
    let onCancel: () -> Void

    @State private var panel: LabPanel
    @State private var valueText: String
    @State private var drawDate: Date
    @State private var source: String
    @State private var note: String
    @State private var showDeleteConfirm: Bool = false

    private var isEditing: Bool { initial != nil }

    init(
        initial: LabValue?,
        onSave: @escaping (LabValue) -> Void,
        onDelete: ((UUID) -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        self.initial = initial
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _panel = State(initialValue: initial?.panel ?? .totalTestosterone)
        _valueText = State(initialValue: initial.map { Self.formatNumber($0.value) } ?? "")
        _drawDate = State(initialValue: initial?.date ?? Date())
        _source = State(initialValue: initial?.source ?? "")
        _note = State(initialValue: initial?.note ?? "")
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(value)
    }

    private var parsedValue: Double? { Self.parseDecimal(valueText) }

    private static func parseDecimal(_ s: String) -> Double? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = .current
        if let n = f.number(from: trimmed) { return n.doubleValue }
        return Double(trimmed)
    }

    private var canSave: Bool {
        guard let value = parsedValue, value > 0 else { return false }
        return rangeError == nil
    }

    /// Sanity bound — a value 10× beyond the typical-range floor /
    /// ceiling is almost certainly a unit confusion or typo. We
    /// reject save when the value falls outside [floor × 0.1,
    /// ceiling × 10]. Anything narrower would also reject the
    /// 0-ferritin / 999-cholesterol legitimate outliers that
    /// motivate users to track in the first place (audit Biology
    /// MED 12).
    private var rangeError: String? {
        guard let value = parsedValue, let range = panel.typicalRange else { return nil }
        let floor = range.lowerBound * 0.1
        let ceiling = range.upperBound * 10
        if value < floor {
            return "That's way below the typical \(format(range.lowerBound))–\(format(range.upperBound)) \(panel.canonicalUnit). Double-check the unit."
        }
        if value > ceiling {
            return "That's way above the typical \(format(range.lowerBound))–\(format(range.upperBound)) \(panel.canonicalUnit). Double-check the unit."
        }
        return nil
    }

    private func format(_ d: Double) -> String {
        d.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(d)) : String(format: "%.1f", d)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Panel") {
                    Picker("Panel", selection: $panel) {
                        ForEach(LabPanel.Category.allCases) { category in
                            Section(category.displayName) {
                                ForEach(LabPanel.allCases.filter { $0.category == category }) { p in
                                    Text(p.displayName).tag(p)
                                }
                            }
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section {
                    HStack {
                        TextField("Value", text: $valueText)
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                        Text(panel.canonicalUnit)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    if let rangeError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                            Text(rangeError)
                                .font(AppFont.caption)
                        }
                        .foregroundStyle(AppColor.destructive)
                    }
                    // Future draw-dates would break the chart's
                    // time-based axis (audit Biology MED 12). The
                    // `in: ...Date()` bound caps the picker at
                    // today.
                    DatePicker("Drawn on", selection: $drawDate, in: ...Date(), displayedComponents: .date)
                } header: {
                    Text("Result")
                } footer: {
                    if let range = panel.typicalRange {
                        Text(rangeFooter(range: range))
                    } else {
                        Text("Reported in \(panel.canonicalUnit). Convert from your lab's unit before entering.")
                    }
                }

                Section {
                    TextField("Lab / source (optional)", text: $source)
                        .textInputAutocapitalization(.words)
                    TextField("Notes (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Context")
                } footer: {
                    Text("Add the lab name (Quest, Marek Health, your clinic) so multiple draws stay sortable.")
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "trash")
                                Text("Delete entry")
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "Edit lab" : "New lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: commit)
                        .disabled(!canSave)
                }
            }
            .confirmationDialog(
                "Delete this entry?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let initial { onDelete?(initial.id) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone. The trend chart will skip the deleted point.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func rangeFooter(range: ClosedRange<Double>) -> String {
        let low = Self.formatNumber(range.lowerBound)
        let high = Self.formatNumber(range.upperBound)
        return String(
            localized: "Typical adult range: \(low)–\(high) \(panel.canonicalUnit). Your lab may use different reference values.",
            comment: "Lab editor footer — informational reference range."
        )
    }

    private func commit() {
        guard let value = parsedValue else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = LabValue(
            id: initial?.id ?? UUID(),
            date: drawDate,
            panel: panel,
            value: value,
            source: trimmedSource.isEmpty ? nil : trimmedSource,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            updatedAt: Date()
        )
        onSave(entry)
    }
}
