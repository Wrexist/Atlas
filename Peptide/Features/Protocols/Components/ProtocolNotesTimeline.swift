import SwiftUI

/// Per-protocol journal timeline. Surfaces every `ProtocolNote`
/// attached to one protocol, grouped by calendar day, with the
/// most recent day on top. Tap a row to edit; long-press for
/// context menu (edit / delete). "+" in the header opens the
/// editor on a fresh empty note.
///
/// Empty state surfaces the value prop ("capture side effects,
/// mood, energy…") rather than a blank shrug — first impression
/// matters for a feature that's invisible until the user opens it.
struct ProtocolNotesTimeline: View {
    let protocolID: UUID
    let protocolName: String
    let notes: [ProtocolNote]
    let onSave: (ProtocolNote) -> Void
    let onDelete: (UUID) -> Void

    @State private var editingNote: ProtocolNote?
    @State private var creatingNote: Bool = false

    private var groupedByDay: [(Date, [ProtocolNote])] {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: notes) { calendar.startOfDay(for: $0.date) }
        return byDay.sorted { $0.key > $1.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header
            if notes.isEmpty {
                emptyState
            } else {
                ForEach(groupedByDay, id: \.0) { day, dayNotes in
                    daySection(day: day, notes: dayNotes)
                }
            }
        }
        .sheet(item: $editingNote) { note in
            ProtocolNoteEditorSheet(
                initial: note,
                protocolName: protocolName,
                onSave: { saved in
                    onSave(saved)
                    editingNote = nil
                },
                onDelete: { id in
                    onDelete(id)
                    editingNote = nil
                },
                onCancel: { editingNote = nil }
            )
        }
        .sheet(isPresented: $creatingNote) {
            ProtocolNoteEditorSheet(
                initial: ProtocolNote(protocolID: protocolID, body: ""),
                protocolName: protocolName,
                onSave: { saved in
                    onSave(saved)
                    creatingNote = false
                },
                onDelete: nil,
                onCancel: { creatingNote = false }
            )
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Notes")
                    .font(AppFont.scaled(11, weight: .heavy))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.accentLight.opacity(0.85))
                Text(notes.isEmpty ? "Capture what's working" : "\(notes.count) entr\(notes.count == 1 ? "y" : "ies")")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .contentTransition(.numericText())
            }
            Spacer()
            Button {
                creatingNote = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(11, weight: .bold))
                    Text("Add note")
                        .font(AppFont.scaled(11, weight: .semibold))
                }
                .foregroundStyle(AppColor.accentLight)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 6)
                .background {
                    Capsule().fill(AppColor.accentPrimary.opacity(0.18))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "text.bubble")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(AppColor.accentLight)
            Text("No notes yet")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("Capture side effects, energy shifts, mood, anything you want to remember about this protocol.")
                .font(AppFont.scaled(11))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
    }

    private func daySection(day: Date, notes: [ProtocolNote]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(Self.dayFormatter.string(from: day))
                .font(AppFont.scaled(11, weight: .heavy))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.textTertiary)
                .padding(.horizontal, 2)
            VStack(spacing: Spacing.xs) {
                ForEach(notes.sorted(by: { $0.date > $1.date })) { note in
                    row(note)
                }
            }
        }
    }

    private func row(_ note: ProtocolNote) -> some View {
        Button {
            editingNote = note
        } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                if let mood = note.mood {
                    Circle()
                        .fill(moodTint(mood).opacity(0.55))
                        .frame(width: 8, height: 8)
                        .padding(.top, 7)
                } else {
                    Circle()
                        .fill(AppColor.textTertiary.opacity(0.4))
                        .frame(width: 8, height: 8)
                        .padding(.top, 7)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.body)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Self.timeFormatter.string(from: note.date))
                        .font(AppFont.scaled(11))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.45))
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { editingNote = note } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDelete(note.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Same warm-to-cool palette `OutcomeDimension` uses. Mapped
    /// onto the 1-5 mood scale so the timeline reads as a single
    /// design idiom across check-ins and notes.
    private func moodTint(_ mood: Int) -> Color {
        switch mood {
        case 5:  Color(red: 0.36, green: 0.78, blue: 0.55)
        case 4:  Color(red: 0.40, green: 0.74, blue: 0.92)
        case 3:  Color(red: 1.00, green: 0.78, blue: 0.20)
        case 2:  Color(red: 0.95, green: 0.62, blue: 0.30)
        case 1:  Color(red: 0.95, green: 0.50, blue: 0.55)
        default: AppColor.textSecondary
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}

/// Inline editor sheet. Title field is implicit (protocol name in
/// the navigation title), body field auto-focuses, optional mood
/// picker beneath. Delete is destructive + confirmed; cancel just
/// dismisses.
struct ProtocolNoteEditorSheet: View {
    let initial: ProtocolNote
    let protocolName: String
    let onSave: (ProtocolNote) -> Void
    let onDelete: ((UUID) -> Void)?
    let onCancel: () -> Void

    @State private var noteBody: String = ""
    @State private var mood: Int?
    @State private var date: Date = Date()
    @State private var showDeleteConfirm: Bool = false
    @FocusState private var focused: Bool

    private var isEditing: Bool { onDelete != nil }
    private var canSave: Bool {
        !noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What happened?", text: $noteBody, axis: .vertical)
                        .focused($focused)
                        .lineLimit(4...10)
                        .textInputAutocapitalization(.sentences)
                } header: {
                    Text("Note")
                } footer: {
                    Text("Side effects, energy, mood, anything you want to remember. Visible only to you.")
                }

                Section("When") {
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }

                Section {
                    moodPicker
                } header: {
                    Text("Mood (optional)")
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete note", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(protocolName)
            .navigationBarTitleDisplayMode(.inline)
            .glassFormStyle()
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
                "Delete this note?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    onDelete?(initial.id)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            self.noteBody = initial.body
            self.mood = initial.mood
            self.date = initial.date
            // Auto-focus the body field on a fresh note so the
            // user starts typing immediately. Existing edits skip
            // the focus to avoid an unwanted keyboard pop.
            if !isEditing && initial.body.isEmpty {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    focused = true
                }
            }
        }
    }

    private var moodPicker: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(1...5, id: \.self) { rating in
                moodButton(rating: rating)
            }
            // None / clear option — surfaces as a "no mood"
            // affordance for users who don't want to commit to
            // a number. Wider tap target than the digits since
            // it's also the "deselect" path.
            Button {
                Haptics.impact(.light)
                mood = nil
            } label: {
                Image(systemName: "xmark.circle")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear mood")
        }
    }

    private func moodButton(rating: Int) -> some View {
        let active = mood == rating
        return Button {
            Haptics.impact(.light)
            mood = rating
        } label: {
            Text("\(rating)")
                .font(AppFont.scaled(16, weight: active ? .heavy : .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(active ? AppColor.textPrimary : AppColor.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .fill(active ? AppColor.accentPrimary.opacity(0.25) : AppColor.surfaceSecondary.opacity(0.45))
                        .overlay {
                            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                .strokeBorder(
                                    active ? AppColor.accentPrimary.opacity(0.55) : AppColor.glassBorder,
                                    lineWidth: 1
                                )
                        }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mood \(rating) of 5")
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }

    private func commit() {
        Haptics.success()
        let trimmed = noteBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = ProtocolNote(
            id: initial.id,
            protocolID: initial.protocolID,
            date: date,
            body: trimmed,
            mood: mood,
            updatedAt: Date()
        )
        onSave(saved)
    }
}
