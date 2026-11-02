import SwiftUI

/// Name, dose, time of day and reminder for one supplement. Only the name
/// is required; the time of day orders the Today rows and is what a
/// reminder fires at.
struct SupplementEditSheet: View {
    let supplement: Supplement
    let isNew: Bool
    let onSave: (Supplement) -> Void
    let onDelete: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var name: String
    @State private var dose: String
    @State private var minuteOfDay: Int?
    @State private var reminderEnabled: Bool
    @State private var showingDeleteConfirm = false
    @State private var notificationsDenied = false

    @FocusState private var nameFocused: Bool

    init(
        supplement: Supplement,
        isNew: Bool,
        onSave: @escaping (Supplement) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) {
        self.supplement = supplement
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: supplement.name)
        _dose = State(initialValue: supplement.dose)
        _minuteOfDay = State(initialValue: supplement.minuteOfDay)
        _reminderEnabled = State(initialValue: supplement.reminderEnabled)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    medallion
                    VStack(spacing: Spacing.md) {
                        GlassTextField(placeholder: "Name", text: $name, icon: nil, focus: $nameFocused)
                            .submitLabel(.done)
                        GlassTextField(placeholder: "Dose (optional)", text: $dose, icon: nil)
                            .submitLabel(.done)
                    }
                    timeSection
                    if !isNew {
                        deleteButton
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.lg)
                .readableContentWidth()
            }
            .background(AppColor.background.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .pinnedFooter {
                PrimaryCTAButton(title: isNew ? "Add supplement" : "Save changes", icon: isNew ? "plus" : nil) {
                    commit()
                }
                .disabled(trimmedName.isEmpty)
            }
            .navigationTitle(isNew ? "New supplement" : "Edit supplement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if isNew { nameFocused = true }
            }
            .task {
                if reminderEnabled {
                    notificationsDenied = await NotificationService.shared.checkAuthorization() == .denied
                }
            }
            // Asking here is what lets the reminder fire for someone who
            // skipped notifications in onboarding.
            .onChange(of: reminderEnabled) { _, enabled in
                guard enabled else { return }
                Task {
                    notificationsDenied = !(await NotificationService.shared.requestAuthorization())
                }
            }
        }
    }

    private var medallion: some View {
        Image(systemName: supplement.symbol)
            .font(AppFont.scaled(32, weight: .semibold, relativeTo: .title1))
            .foregroundStyle(AppColor.accentLight)
            .frame(width: 88, height: 88)
            .background {
                Circle()
                    .fill(AppColor.accentPrimary.opacity(0.12))
                    .overlay { Circle().strokeBorder(AppColor.accentPrimary.opacity(0.5), lineWidth: 1.5) }
            }
            .accessibilityHidden(true)
    }

    // MARK: - Time and reminder

    /// Three parts of the day rather than a clock; tapping the selected
    /// one again makes it "any time".
    private var timeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Time of day")
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Spacing.sm) {
                ForEach(HabitReminderSlot.allCases) { slot in
                    timeChip(slot)
                }
            }

            if let minuteOfDay {
                reminderToggle(minuteOfDay: minuteOfDay)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                if reminderEnabled && notificationsDenied {
                    notificationsDeniedRow
                }
            } else {
                Text("Pick a time of day to get a reminder.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
        .appAnimation(AppAnimation.springSnappy, value: minuteOfDay)
    }

    private func timeChip(_ slot: HabitReminderSlot) -> some View {
        let isSelected = minuteOfDay == slot.hour * 60
        return Button {
            Haptics.selection()
            AppAnimation.with(AppAnimation.springSnappy) {
                minuteOfDay = isSelected ? nil : slot.hour * 60
            }
        } label: {
            VStack(spacing: Spacing.xs) {
                Image(systemName: slot.icon)
                    .font(AppFont.scaled(16, weight: .medium))
                    .accessibilityHidden(true)
                Text(slot.title)
                    .font(AppFont.chipText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isSelected ? AppColor.accentLight : AppColor.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .frame(minHeight: Spacing.minimumHitTarget)
            .glassControl(
                .rect(cornerRadius: Spacing.controlCornerRadius),
                tint: isSelected ? AppColor.accentPrimary.opacity(0.18) : nil,
                border: isSelected ? AppColor.glassBorderActive : AppColor.glassBorder,
                interactive: false
            )
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func reminderToggle(minuteOfDay: Int) -> some View {
        let time = Supplement(name: name, minuteOfDay: minuteOfDay).timeText() ?? ""
        return Toggle(isOn: $reminderEnabled) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Remind me")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textPrimary)
                Text("At \(time), until it's checked off")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
        .tint(AppColor.accentPrimary)
        .padding(Spacing.lg)
        .glassSurface(cornerRadius: Spacing.controlCornerRadius)
    }

    private var notificationsDeniedRow: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(AppFont.scaled(11))
                    .foregroundStyle(AppColor.warning)
                    .accessibilityHidden(true)
                Text("Notifications are off for Atlas. Turn them on in Settings.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(minHeight: Spacing.minimumHitTarget)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Delete

    private var deleteButton: some View {
        GlassButton(title: "Delete supplement", icon: "trash", style: .destructive, isFullWidth: true) {
            showingDeleteConfirm = true
        }
        .confirmationDialog("Delete this supplement?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                onDelete(supplement.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes it and its history from your list. This can't be undone.")
        }
    }

    // MARK: - Commit

    private func commit() {
        guard !trimmedName.isEmpty else { return }
        var updated = supplement
        updated.name = trimmedName
        updated.dose = dose.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.minuteOfDay = minuteOfDay
        updated.reminderEnabled = minuteOfDay != nil && reminderEnabled
        Haptics.success()
        onSave(updated)
        dismiss()
    }
}
