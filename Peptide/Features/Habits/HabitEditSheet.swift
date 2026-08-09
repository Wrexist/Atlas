import SwiftUI

/// Create / edit a single Habit.
///
/// The shape of the screen is the claim that a habit is cheap to make:
/// medallion, name, how often, and a reminder — four decisions, all
/// visible at once, none of them required beyond the name. Everything
/// else the model exposes (category, icon, colour, a numeric target, an
/// exact reminder time) lives one push away behind Customize, so the
/// common path stays type-and-add.
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

    @FocusState private var nameFocused: Bool

    enum ScheduleKind: String, CaseIterable, Identifiable {
        case daily, weekdays, timesPerWeek
        var id: String { rawValue }
        var displayName: LocalizedStringKey {
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
        _reminderTime = State(initialValue: base.reminderTime ?? HabitReminderSlot.morning.time())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    medallion
                    nameField
                    scheduleSection
                    customizeRow
                    reminderSection
                    if editing != nil, onDelete != nil {
                        deleteButton
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.lg)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(AppColor.background.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .pinnedFooter {
                PrimaryCTAButton(title: ctaTitle, icon: editing == nil ? "plus" : nil) {
                    commit()
                }
                .disabled(!canSave)
            }
            .navigationTitle(editing == nil ? "New Habit" : "Edit Habit")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: CustomizeRoute.self) { _ in
                HabitCustomizeView(
                    category: $category,
                    iconSymbol: $iconSymbol,
                    tintHex: $tintHex,
                    enableTarget: $enableTarget,
                    targetValue: $targetValue,
                    enableReminder: $enableReminder,
                    reminderTime: $reminderTime
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { commit() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                if editing == nil { nameFocused = true }
            }
        }
    }

    /// `navigationDestination` needs a value type to key on, and Customize
    /// is the only push this screen has.
    private struct CustomizeRoute: Hashable {}

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var ctaTitle: LocalizedStringKey {
        editing == nil ? "Add habit" : "Save changes"
    }

    private var tint: Color { Color(hex: UInt(tintHex)) }

    // MARK: - Identity

    /// The habit's icon and colour, at the size that makes them feel like
    /// a choice worth making. Tapping it goes to the same place Customize
    /// does — it's the picker, not decoration.
    private var medallion: some View {
        NavigationLink(value: CustomizeRoute()) {
            Image(systemName: iconSymbol)
                .font(AppFont.scaled(32, weight: .semibold, relativeTo: .title1))
                .foregroundStyle(tint)
                .frame(width: 88, height: 88)
                .background {
                    Circle().strokeBorder(tint.opacity(0.5), lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Icon and colour")
        .accessibilityHint("Opens the icon and colour pickers")
    }

    private var nameField: some View {
        TextField("Habit name", text: $name)
            .font(AppFont.body)
            .focused($nameFocused)
            .submitLabel(.done)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .frame(minHeight: Spacing.minimumHitTarget)
            .background {
                RoundedRectangle(cornerRadius: Spacing.controlCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary)
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.controlCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 1)
                    }
            }
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Schedule")

            settingCard {
                HStack {
                    Text("Frequency")
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer(minLength: Spacing.sm)
                    Menu {
                        Picker("Frequency", selection: $scheduleKind) {
                            ForEach(ScheduleKind.allCases) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Text(scheduleKind.displayName)
                                .font(AppFont.body)
                                .fontWeight(.semibold)
                            Image(systemName: "chevron.down")
                                .font(AppFont.scaled(11, weight: .bold))
                        }
                        .foregroundStyle(AppColor.accentLight)
                        .minimumHitArea()
                    }
                }
            }

            switch scheduleKind {
            case .daily:
                EmptyView()
            case .weekdays:
                settingCard { weekdayPicker }
            case .timesPerWeek:
                settingCard {
                    Stepper(value: $timesPerWeek, in: 1...7) {
                        Text("\(timesPerWeek) times per week")
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textPrimary)
                    }
                }
            }
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(HabitWeekday.allCases.sorted(by: { $0.calendarOrder < $1.calendarOrder }), id: \.self) { day in
                let isSelected = weekdays.contains(day)
                // Deselecting the LAST remaining day is disabled so the
                // user can't end up with an empty set that commit()
                // silently rewrites to "all days" — they think they
                // picked nothing and got daily (audit Habits H6).
                let isLastSelected = isSelected && weekdays.count == 1
                Button {
                    Haptics.impact(.soft)
                    if isSelected { weekdays.remove(day) } else { weekdays.insert(day) }
                } label: {
                    Text(day.shortName)
                        .font(AppFont.scaled(13, weight: .bold))
                        .foregroundStyle(isSelected ? AppColor.onAccent : AppColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: Spacing.minimumHitTarget)
                        .background {
                            Circle().fill(isSelected ? tint : AppColor.surfaceElevated)
                        }
                }
                .buttonStyle(.plain)
                .disabled(isLastSelected)
                .accessibilityLabel(day.fullName)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
    }

    // MARK: - Customize

    private var customizeRow: some View {
        NavigationLink(value: CustomizeRoute()) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "slider.horizontal.3")
                    .font(AppFont.scaled(20, weight: .medium))
                    .foregroundStyle(AppColor.accentLight)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Customize")
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Icon, color, target, reminder")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: Spacing.controlCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary)
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.controlCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Reminder

    /// Three times of day rather than a clock. Most habits belong to a
    /// part of the day, not a minute of it, and the exact time is still
    /// there under Customize for the ones that do. Tapping the selected
    /// slot again turns the reminder off.
    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Reminder")
            HStack(spacing: Spacing.sm) {
                ForEach(HabitReminderSlot.allCases) { slot in
                    reminderChip(slot)
                }
            }
        }
    }

    private func reminderChip(_ slot: HabitReminderSlot) -> some View {
        let isSelected = enableReminder && HabitReminderSlot(matching: reminderTime) == slot
        return Button {
            Haptics.impact(.soft)
            if isSelected {
                enableReminder = false
            } else {
                enableReminder = true
                reminderTime = slot.time()
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: slot.icon)
                    .font(AppFont.scaled(16, weight: .medium))
                Text(slot.title)
                    .font(AppFont.scaled(13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isSelected ? AppColor.accentLight : AppColor.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .frame(minHeight: Spacing.minimumHitTarget)
            .background {
                RoundedRectangle(cornerRadius: Spacing.controlCornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? AppColor.glassBorderActive : AppColor.glassBorder,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(slot.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Delete

    private var deleteButton: some View {
        GlassButton(title: "Delete habit",
                    icon: "trash",
                    style: .destructive,
                    isFullWidth: true) {
            showingDeleteConfirm = true
        }
        .confirmationDialog(
            "Delete this habit?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let editing { onDelete?(editing.id) }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your streak and history are kept and can be restored from settings.")
        }
    }

    // MARK: - Shared chrome

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(AppFont.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(AppColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingCard<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        content()
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: Spacing.controlCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary)
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.controlCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 1)
                    }
            }
    }

    // MARK: - Commit

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

        // Re-anchor the reminder to today's date with the chosen hour +
        // minute — keeps the stored value semantically a "time of day"
        // while avoiding the year-0001 timestamp a date-less
        // DateComponents produces (audit M9). NotificationService only
        // reads hour + minute, so the date component here is cosmetic.
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

/// The three parts of a day a habit can be pinned to. Backed by
/// `Habit.reminderTime` — there is no separate stored field, so a habit
/// whose exact time was set under Customize still lands in whichever slot
/// contains it.
enum HabitReminderSlot: String, CaseIterable, Identifiable {
    case morning, afternoon, evening

    var id: String { rawValue }

    var hour: Int {
        switch self {
        case .morning:   return 8
        case .afternoon: return 13
        case .evening:   return 20
        }
    }

    var icon: String {
        switch self {
        case .morning:   return "sun.max"
        case .afternoon: return "sun.horizon"
        case .evening:   return "moon"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .morning:   return "Morning"
        case .afternoon: return "Afternoon"
        case .evening:   return "Evening"
        }
    }

    var accessibilityLabel: LocalizedStringKey {
        switch self {
        case .morning:   return "Remind me in the morning"
        case .afternoon: return "Remind me in the afternoon"
        case .evening:   return "Remind me in the evening"
        }
    }

    /// Today at this slot's hour. Dated rather than date-less so the
    /// stored value stays a real timestamp (audit M9).
    func time(calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = 0
        return calendar.date(from: components) ?? Date()
    }

    /// Which slot a stored reminder falls in. Boundaries sit between the
    /// slot hours, so 11:00 is still morning and 17:00 is afternoon.
    init(matching date: Date, calendar: Calendar = .current) {
        switch calendar.component(.hour, from: date) {
        case ..<11:  self = .morning
        case ..<17:  self = .afternoon
        default:     self = .evening
        }
    }
}
