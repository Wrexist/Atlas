import SwiftUI

/// Log-or-edit sheet for a single `LabValue`. Three inputs (panel,
/// value, date) plus two optional fields (source, note). The
/// panel picker is the most consequential interaction — users
/// don't always know "is total or free testosterone the one I
/// want?" — so the picker exposes each panel's canonical unit and
/// category as supporting context.
struct LabEntryEditor: View {
    let initial: LabValue?
    /// User's sex so the reference-range footer and sanity bounds use
    /// the correct interval for sex-specific panels.
    let sex: BiologicalSex
    let onSave: (LabValue) -> Void
    let onDelete: ((UUID) -> Void)?
    let onCancel: () -> Void

    @State private var panel: LabPanel
    @State private var valueText: String
    @State private var drawDate: Date
    @State private var source: String
    @State private var note: String
    /// The user typed the value in the panel's SI unit; `commit()`
    /// converts it to the canonical unit.
    @State private var reportedInSI = false
    @State private var showDeleteConfirm: Bool = false
    /// Out-of-range warning, shown only once typing pauses so "1" on the
    /// way to "1000" doesn't flash an error.
    @State private var showRangeWarning = false
    @State private var showSaveAnywayConfirm = false
    @FocusState private var valueFocused: Bool

    private var isEditing: Bool { initial != nil }

    /// `.other` is reserved for the custom-panel editor and has no name or
    /// unit, so it's offered only to an entry that already is one.
    private func pickablePanels(in category: LabPanel.Category) -> [LabPanel] {
        LabPanel.allCases.filter { $0.category == category && ($0 != .other || initial?.panel == .other) }
    }

    /// `defaultPanel` pre-selects the panel for a new entry — the panel
    /// being viewed, or the one the user logged most recently.
    /// `carryOver` pre-fills a new entry's draw date and lab from the
    /// entry just saved (see `carryOverEntry(from:now:)`).
    init(
        initial: LabValue?,
        defaultPanel: LabPanel? = nil,
        carryOver: LabValue? = nil,
        sex: BiologicalSex,
        onSave: @escaping (LabValue) -> Void,
        onDelete: ((UUID) -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        self.initial = initial
        self.sex = sex
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _panel = State(initialValue: initial?.panel ?? defaultPanel.flatMap { $0 == .other ? nil : $0 } ?? .vitaminD)
        _valueText = State(initialValue: initial.map { LabValueFormat.string($0.value) } ?? "")
        let prefill = initial ?? carryOver
        _drawDate = State(initialValue: prefill?.date ?? Date())
        _source = State(initialValue: prefill?.source ?? "")
        _note = State(initialValue: initial?.note ?? "")
    }

    /// How recently an entry must have been saved for the next new one to
    /// be treated as part of the same report.
    static let carryOverWindow: TimeInterval = 60 * 60

    /// The entry saved last, when that was within `carryOverWindow` of
    /// `now`. One report carries many markers with one draw date and one
    /// lab, so the next entry starts from those instead of today and blank.
    static func carryOverEntry(from entries: [LabValue], now: Date) -> LabValue? {
        guard let last = entries.max(by: { $0.updatedAt < $1.updatedAt }) else { return nil }
        let elapsed = now.timeIntervalSince(last.updatedAt)
        return elapsed >= 0 && elapsed <= carryOverWindow ? last : nil
    }

    private var usesSI: Bool { reportedInSI && panel.siUnit != nil }

    private var parsedValue: Double? { Self.parseDecimal(valueText) }

    /// The typed value converted to `panel.canonicalUnit`.
    private var canonicalValue: Double? {
        guard let value = parsedValue else { return nil }
        return usesSI ? panel.canonicalValue(fromSI: value) : value
    }

    private static let decimalParser: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = .current
        return f
    }()

    /// The typed number, or nil when it isn't one. `Double(_:)` also
    /// accepts "inf" and "1e999", which would break the chart's axis and
    /// the change percentage, so non-finite results are rejected.
    static func parseDecimal(_ s: String) -> Double? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parsed = decimalParser.number(from: trimmed)?.doubleValue ?? Double(trimmed)
        return parsed.flatMap { $0.isFinite ? $0 : nil }
    }

    private var canSave: Bool {
        guard let value = parsedValue, let canonical = canonicalValue else { return false }
        return value >= 0 && canonical.isFinite
    }

    /// Sanity bound — a value 10× beyond the typical-range floor /
    /// ceiling is almost certainly a unit confusion or typo. It warns
    /// and asks before saving rather than blocking: the
    /// 0-ferritin / 999-cholesterol outliers are exactly what
    /// motivates users to track in the first place (audit Biology
    /// MED 12).
    private var rangeWarning: String? {
        guard let value = canonicalValue, let range = panel.typicalRange(for: sex) else { return nil }
        let low = LabValueFormat.string(range.lowerBound)
        let high = LabValueFormat.string(range.upperBound)
        let unit = panel.canonicalUnit
        if value < range.lowerBound * 0.1 {
            return String(localized: "Below the usual \(low)–\(high) \(unit). Check the unit your lab used.")
        }
        if value > range.upperBound * 10 {
            return String(localized: "Above the usual \(low)–\(high) \(unit). Check the unit your lab used.")
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Panel") {
                    Picker("Panel", selection: $panel) {
                        ForEach(LabPanel.Category.allCases) { category in
                            Section(category.displayName) {
                                ForEach(pickablePanels(in: category)) { p in
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
                            .focused($valueFocused)
                        if let siUnit = panel.siUnit {
                            Picker("Unit", selection: $reportedInSI) {
                                Text(panel.canonicalUnit).tag(false)
                                Text(siUnit).tag(true)
                            }
                            .pickerStyle(.segmented)
                            .fixedSize()
                        } else {
                            Text(panel.canonicalUnit)
                                .font(AppFont.caption2)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                    if showRangeWarning, let rangeWarning {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(AppFont.scaled(11))
                                .accessibilityHidden(true)
                            Text(rangeWarning)
                                .font(AppFont.caption2)
                        }
                        .foregroundStyle(AppColor.warning)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    // Future draw-dates would break the chart's
                    // time-based axis (audit Biology MED 12). The
                    // `in: ...Date()` bound caps the picker at
                    // today.
                    DatePicker("Drawn on", selection: $drawDate, in: ...Date(), displayedComponents: .date)
                } header: {
                    Text("Result")
                } footer: {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        if let range = panel.typicalRange(for: sex) {
                            Text(rangeFooter(range: range))
                        }
                        if panel.siUnit == nil {
                            Text("Reported in \(panel.canonicalUnit). Convert from your lab's unit before entering.")
                        }
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
                    Text("Add the lab name (e.g. Quest, Labcorp, your clinic) so multiple draws stay sortable.")
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete entry", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .appAnimation(AppAnimation.springSnappy, value: showRangeWarning)
            .task(id: valueText) {
                // Debounce: judge the value once typing pauses.
                showRangeWarning = false
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                showRangeWarning = rangeWarning != nil
            }
            .onChange(of: reportedInSI) { _, _ in
                showRangeWarning = rangeWarning != nil && !valueText.isEmpty
            }
            .onChange(of: panel) { _, _ in
                showRangeWarning = rangeWarning != nil && !valueText.isEmpty
            }
            .onAppear {
                if !isEditing { valueFocused = true }
            }
            .navigationTitle(isEditing ? "Edit lab" : "New lab")
            .navigationBarTitleDisplayMode(.inline)
            .glassFormStyle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: attemptSave)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { valueFocused = false }
                }
            }
            .confirmationDialog(
                "Save this value?",
                isPresented: $showSaveAnywayConfirm,
                titleVisibility: .visible
            ) {
                Button("Save anyway", action: commit)
                Button("Edit value", role: .cancel) { valueFocused = true }
            } message: {
                Text(rangeWarning ?? "")
            }
            .confirmationDialog(
                "Delete this entry?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Haptics.warning()
                    if let initial { onDelete?(initial.id) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone. The trend chart will skip the deleted point.")
            }
        }
    }

    private func rangeFooter(range: ClosedRange<Double>) -> String {
        let low = LabValueFormat.string(range.lowerBound)
        let high = LabValueFormat.string(range.upperBound)
        return String(
            localized: "Typical adult range: \(low)–\(high) \(panel.canonicalUnit). Your lab may use different reference values.",
            comment: "Lab editor footer — informational reference range."
        )
    }

    /// Saves straight through unless the value looks like a unit slip,
    /// in which case it asks first.
    private func attemptSave() {
        if rangeWarning != nil {
            showRangeWarning = true
            Haptics.warning()
            showSaveAnywayConfirm = true
        } else {
            commit()
        }
    }

    private func commit() {
        guard let value = canonicalValue, value.isFinite else { return }
        Haptics.success()
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
