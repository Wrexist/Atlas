import SwiftUI

/// "How are you feeling today?" on the Biology tab: one tap logs today's
/// mood, a note says why, and Ask Atlas can read the last two weeks next
/// to the signals. The journal stays on this device.
struct HealthJournalCard: View {
    var onReflect: () -> Void

    @State private var store = HealthJournalStore.shared
    @State private var editingNote = false
    @State private var showHistory = false

    private var today: HealthJournalEntry? { store.entry(on: .now) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                BiologySectionHeader(title: "Journal", subtitle: "How are you feeling today?")
                if !store.entries.isEmpty {
                    Button("See all") { showHistory = true }
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.accentLight)
                        .minimumHitArea()
                        .buttonStyle(.plain)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    moodPicker
                    if let today {
                        noteRow(today)
                    }
                    if store.entries.count >= 3 {
                        Button(action: onReflect) {
                            Label("Find patterns in your journal", systemImage: "sparkles")
                                .font(AppFont.scaled(16, weight: .semibold))
                                .foregroundStyle(AppColor.accentLight)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .minimumHitArea()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .biologyCardReveal()
        .sheet(isPresented: $editingNote) {
            if let today {
                HealthJournalNoteSheet(entry: today) { note in
                    store.save(mood: today.mood, note: note)
                }
                .liquidGlassPresentation(detents: [.medium, .large])
            }
        }
        .sheet(isPresented: $showHistory) {
            HealthJournalHistorySheet()
                .liquidGlassPresentation()
        }
    }

    private var moodPicker: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(HealthJournalEntry.Mood.allCases, id: \.self) { mood in
                let selected = today?.mood == mood
                Button {
                    Haptics.selection()
                    AppAnimation.with(AppAnimation.springSnappy) {
                        store.save(mood: mood, note: today?.note ?? "")
                    }
                } label: {
                    VStack(spacing: Spacing.xs) {
                        Image(systemName: mood.icon)
                            .font(AppFont.scaled(20, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(selected ? mood.tint : AppColor.textTertiary)
                            .frame(width: 44, height: 44)
                            .background {
                                Circle().fill(selected ? mood.tint.opacity(0.18) : AppColor.surfaceSecondary.opacity(0.5))
                            }
                        Text(mood.label)
                            .font(AppFont.scaled(11, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? AppColor.textPrimary : AppColor.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ScalePressStyle(pressedScale: 0.94))
                .accessibilityLabel(Text(mood.label))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func noteRow(_ entry: HealthJournalEntry) -> some View {
        Button { editingNote = true } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: entry.note.isEmpty ? "square.and.pencil" : "text.quote")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .accessibilityHidden(true)
                Text(entry.note.isEmpty ? String(localized: "Add a note about today") : entry.note)
                    .font(AppFont.scaled(16))
                    .foregroundStyle(entry.note.isEmpty ? AppColor.textSecondary : AppColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension HealthJournalEntry.Mood {
    var label: String {
        switch self {
        case .awful: String(localized: "Awful")
        case .low:   String(localized: "Low")
        case .okay:  String(localized: "Okay")
        case .good:  String(localized: "Good")
        case .great: String(localized: "Great")
        }
    }

    var icon: String {
        switch self {
        case .awful: "cloud.bolt.rain.fill"
        case .low:   "cloud.rain.fill"
        case .okay:  "cloud.sun.fill"
        case .good:  "sun.max.fill"
        case .great: "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .awful: AppColor.negative
        case .low:   AppColor.warning
        case .okay:  AppColor.textSecondary
        case .good:  AppColor.metricSleep
        case .great: AppColor.positive
        }
    }
}

/// Writes or edits the note for one journal day.
struct HealthJournalNoteSheet: View {
    let entry: HealthJournalEntry
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @FocusState private var focused: Bool

    init(entry: HealthJournalEntry, onSave: @escaping (String) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _note = State(initialValue: entry.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Sleep, stress, training, how your body feels…", text: $note, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($focused)
                } footer: {
                    Text("Stays on this device. Ask Atlas reads it only when you allow it.")
                }
            }
            .glassFormStyle()
            .navigationTitle(entry.day.formatted(.dateTime.weekday(.wide).day().month()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(note)
                        dismiss()
                    }
                }
            }
            .onAppear { focused = true }
        }
    }
}

/// Every journal day, newest first, with swipe to delete.
struct HealthJournalHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = HealthJournalStore.shared

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.entries) { entry in
                    HStack(alignment: .top, spacing: Spacing.md) {
                        Image(systemName: entry.mood.icon)
                            .font(AppFont.scaled(16, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(entry.mood.tint)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(entry.day.formatted(.dateTime.weekday(.abbreviated).day().month()))
                                .font(AppFont.scaled(16, weight: .semibold))
                                .foregroundStyle(AppColor.textPrimary)
                            Text(entry.mood.label)
                                .font(AppFont.scaled(13))
                                .foregroundStyle(AppColor.textSecondary)
                            if !entry.note.isEmpty {
                                Text(entry.note)
                                    .font(AppFont.scaled(16))
                                    .foregroundStyle(AppColor.textPrimary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .listRowBackground(Color.clear)
                }
                .onDelete { offsets in
                    for id in offsets.map({ store.entries[$0].id }) { store.delete(id: id) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColor.background)
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
