import SwiftUI

/// Create / edit a single Habit. Surfaces every customization knob
/// the model exposes — name, icon, color, category, schedule (daily
/// / weekdays / times-per-week), optional target count, optional
/// reminder time. Submits to `DataStore.addHabit` or `updateHabit`
/// depending on whether `editing` is non-nil.
struct HabitEditSheet: View {
    let editing: Habit?
    let onSave: (Habit) -> Void
    let onDelete: ((UUID) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var iconSymbol: String
    @State private var tintHex: UInt32
    @State private var scheduleKind: ScheduleKind
    @State private var weekdays: Set<HabitWeekday>
    @State private var timesPerWeek: Int
    @State private var enableTarget: Bool
    @State private var targetValue: Int
    @State private var enableReminder: Bool
    @State private var reminderTime: Date
    @State private var category: HabitCategory
    @State private var showingDeleteConfirm: Bool = false
    /// Hides Category / Icon / Color / Target / Reminder behind a
    /// single "Customize" disclosure so the create-form is a
    /// type-and-save flow by default. The user can tap Customize to
    /// reveal the rest. Edit mode opens with the section expanded
    /// since the user is editing an existing habit and probably
    /// wants the knobs visible.
    @State private var showingCustomization: Bool

    @FocusState private var nameFocused: Bool

    enum ScheduleKind: String, CaseIterable, Identifiable {
        case daily, weekdays, timesPerWeek
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .daily:         return "Daily"
            case .weekdays:      return "Specific days"
            case .timesPerWeek:  return "Times per week"
            }
        }
    }

    init(
        editing: Habit?,
        onSave: @escaping (Habit) -> Void,
        onDelete: ((UUID) -> Void)? = nil
    ) {
        self.editing = editing
        self.onSave = onSave
        self.onDelete = onDelete

        let base = editing ?? Habit(
            name: "",
            iconSymbol: HabitIconCatalog.all.first ?? "checkmark.circle.fill",
            tintHex: HabitTintCatalog.all.first ?? 0x6B8AFF
        )
        _name = State(initialValue: base.name)
        _iconSymbol = State(initialValue: base.iconSymbol)
        _tintHex = State(initialValue: base.tintHex)
        _category = State(initialValue: base.category)

        switch base.schedule {
        case .daily:
            _scheduleKind = State(initialValue: .daily)
            _weekdays = State(initialValue: Set(HabitWeekday.allCases))
            _timesPerWeek = State(initialValue: 3)
        case .weekdays(let days):
            _scheduleKind = State(initialValue: .weekdays)
            _weekdays = State(initialValue: days)
            _timesPerWeek = State(initialValue: 3)
        case .timesPerWeek(let n):
            _scheduleKind = State(initialValue: .timesPerWeek)
            _weekdays = State(initialValue: Set(HabitWeekday.allCases))
            _timesPerWeek = State(initialValue: n)
        }

        _enableTarget = State(initialValue: base.targetValue != nil)
        _targetValue = State(initialValue: base.targetValue ?? 8)
        _enableReminder = State(initialValue: base.reminderTime != nil)
        _reminderTime = State(initialValue: base.reminderTime ?? Self.defaultReminderTime())
        _showingCustomization = State(initialValue: editing != nil)
    }

    /// Default reminder time anchored to TODAY at 8:00 AM. The
    /// DatePicker only reads hour + minute, but the underlying Date
    /// shouldn't be year 0001 (the previous impl produced a 2000-
    /// year-old timestamp from a date-less DateComponents, which is
    /// semantically wrong and trips anything that does direct
    /// equality on the Date later — audit M9).
    private static func defaultReminderTime() -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 8
        components.minute = 0
        return calendar.date(from: components) ?? Date()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Habit name", text: $name)
                        .font(AppFont.body)
                        .focused($nameFocused)
                        .submitLabel(.done)
                }

                Section("Schedule") {
                    Picker("Frequency", selection: $scheduleKind) {
                        ForEach(ScheduleKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    if scheduleKind == .weekdays {
                        weekdayPicker
                    } else if scheduleKind == .timesPerWeek {
                        Stepper("\(timesPerWeek) times per week", value: $timesPerWeek, in: 1...7)
                    }
                }

                Section {
                    DisclosureGroup(isExpanded: $showingCustomization) {
                        // Inside-disclosure pickers — collapsed by
                        // default on Create so the user can save in
                        // two taps (type name → Save). Edit mode
                        // opens with this expanded.
                        Picker("Category", selection: $category) {
                            ForEach(HabitCategory.allCases) { c in
                                Label(c.displayName, systemImage: c.icon).tag(c)
                            }
                        }
                        iconGrid
                        colorGrid
                        Toggle("Track a count", isOn: $enableTarget)
                        if enableTarget {
                            Stepper(value: $targetValue, in: 1...100000, step: targetStep) {
                                HStack {
                                    Text("Target")
                                    Spacer()
                                    Text("\(targetValue)")
                                        .foregroundStyle(AppColor.textSecondary)
                                }
                            }
                            Text(targetHint)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textTertiary)
                        }
                        Toggle("Daily reminder", isOn: $enableReminder)
                        if enableReminder {
                            DatePicker(
                                "Time",
                                selection: $reminderTime,
                                displayedComponents: .hourAndMinute
                            )
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Customize", systemImage: "slider.horizontal.3")
                                .foregroundStyle(AppColor.textPrimary)
                            Text("Icon, color, target, reminder")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textTertiary)
                        }
                    }
                }

                if editing != nil, let onDelete {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete habit", systemImage: "trash")
                        }
                    }
                    .confirmationDialog(
                        "Delete this habit?",
                        isPresented: $showingDeleteConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) {
                            if let editing { onDelete(editing.id) }
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Your streak and history are kept and can be restored from settings.")
                    }
                }
            }
            .navigationTitle(editing == nil ? "New Habit" : "Edit Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { commit() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                if editing == nil { nameFocused = true }
            }
        }
    }

    private var iconGrid: some View {
        // `.adaptive` so the grid reflows to fit the available width
        // (Form row width varies between iPhone SE and iPad split-
        // view); the hard-coded 6-column count broke on the narrowest
        // iPhone, where the 36pt minimum × 6 wouldn't fit (audit 4.13).
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 40, maximum: 48), spacing: Spacing.sm)],
                  spacing: Spacing.sm) {
            ForEach(HabitIconCatalog.all, id: \.self) { symbol in
                Button {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    iconSymbol = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(iconSymbol == symbol ? Color(hex: UInt(tintHex)) : AppColor.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(iconSymbol == symbol
                                      ? Color(hex: UInt(tintHex)).opacity(0.18)
                                      : AppColor.surfaceSecondary.opacity(0.6))
                        )
                        .overlay(
                            Circle().stroke(
                                iconSymbol == symbol ? Color(hex: UInt(tintHex)) : Color.clear,
                                lineWidth: 1
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbol)
                .accessibilityAddTraits(iconSymbol == symbol ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private var colorGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 36, maximum: 44), spacing: Spacing.sm)],
                  spacing: Spacing.sm) {
            ForEach(HabitTintCatalog.all, id: \.self) { hex in
                Button {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    tintHex = hex
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: UInt(hex)))
                            .frame(width: 32, height: 32)
                        if tintHex == hex {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .overlay(
                        Circle().stroke(
                            tintHex == hex ? Color.white.opacity(0.9) : Color.clear,
                            lineWidth: 1.5
                        )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color")
                .accessibilityAddTraits(tintHex == hex ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach(HabitWeekday.allCases.sorted(by: { $0.calendarOrder < $1.calendarOrder })) { day in
                let isSelected = weekdays.contains(day)
                // Disable deselecting the LAST remaining day so the
                // user can't end up with an empty set that commit()
                // silently rewrites to "all days." That rewrite is
                // confusing — they think they picked nothing and got
                // daily (audit Habits H6).
                let isLastSelected = isSelected && weekdays.count == 1
                Button {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    if isSelected { weekdays.remove(day) } else { weekdays.insert(day) }
                } label: {
                    Text(day.shortName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isSelected ? AppColor.background : AppColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            Circle().fill(isSelected ? Color(hex: UInt(tintHex)) : AppColor.surfaceSecondary.opacity(0.7))
                        )
                }
                .buttonStyle(.plain)
                .disabled(isLastSelected)
                .accessibilityLabel(day.fullName)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
    }

    private var targetStep: Int {
        // Bigger step for big-number targets so the stepper isn't
        // useless at 10000 steps.
        if targetValue >= 10000 { return 500 }
        if targetValue >= 1000  { return 100 }
        if targetValue >= 100   { return 10 }
        return 1
    }

    private var targetHint: String {
        switch category {
        case .health:        return "e.g. 8 (glasses of water), 10000 (steps)"
        case .fitness:       return "e.g. 30 (minutes), 100 (push-ups)"
        case .learning:      return "e.g. 20 (pages), 1 (lesson)"
        case .mindfulness:   return "e.g. 10 (minutes meditating)"
        case .productivity:  return "e.g. 3 (deep-work blocks)"
        case .custom:        return "Set whatever number reads naturally."
        }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let schedule: HabitSchedule
        switch scheduleKind {
        case .daily:
            schedule = .daily
        case .weekdays:
            schedule = .weekdays(weekdays.isEmpty ? Set(HabitWeekday.allCases) : weekdays)
        case .timesPerWeek:
            schedule = .timesPerWeek(timesPerWeek)
        }

        // Re-anchor reminder to today's date with the chosen hour +
        // minute — keeps the stored value semantically a "time of
        // day" while avoiding the year-0001 timestamp the old impl
        // produced (audit M9). NotificationService only needs the
        // hour + minute components to build a DateComponents
        // trigger, so the date component here is cosmetic.
        let normalizedReminder: Date? = {
            guard enableReminder else { return nil }
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            let timeOnly = calendar.dateComponents([.hour, .minute], from: reminderTime)
            components.hour = timeOnly.hour
            components.minute = timeOnly.minute
            return calendar.date(from: components) ?? reminderTime
        }()

        let habit = Habit(
            id: editing?.id ?? UUID(),
            name: trimmed,
            iconSymbol: iconSymbol,
            tintHex: tintHex,
            schedule: schedule,
            targetValue: enableTarget ? targetValue : nil,
            reminderTime: normalizedReminder,
            category: category,
            createdAt: editing?.createdAt ?? Date(),
            sortIndex: editing?.sortIndex ?? 0,
            archived: editing?.archived ?? false
        )
        onSave(habit)
        dismiss()
    }
}
