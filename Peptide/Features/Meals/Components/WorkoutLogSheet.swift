import SwiftUI

/// Lightweight workout log — name, sets, reps, duration. Intentionally
/// not a full gym app per the spec; just enough structure for the
/// Lifestyle-card subtitle to read "N exercises · M min" and for a
/// future Analytics surface to roll the data up. Recent entries list
/// supports swipe-to-delete so typos can be fixed without leaving
/// the sheet.
struct WorkoutLogSheet: View {
    let history: [WorkoutEntry]
    let onLog: (WorkoutEntry) -> Void
    let onDelete: (UUID) -> Void
    let onClose: () -> Void

    @State private var name: String = ""
    @State private var sets: String = ""
    @State private var reps: String = ""
    @State private var minutes: String = ""
    @State private var date: Date = Date()
    @FocusState private var nameFocused: Bool

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && Int(sets) ?? 0 >= 0
            && Int(reps) ?? 0 >= 0
            && Int(minutes) ?? 0 >= 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("New session") {
                    TextField("Exercise or workout name", text: $name)
                        .focused($nameFocused)

                    HStack {
                        Text("Sets")
                        Spacer()
                        TextField("0", text: $sets)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                    }
                    HStack {
                        Text("Reps")
                        Spacer()
                        TextField("0", text: $reps)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                    }
                    HStack {
                        Text("Duration (min)")
                        Spacer()
                        TextField("0", text: $minutes)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                    }
                    DatePicker("When", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }

                if !history.isEmpty {
                    Section("Recent sessions") {
                        ForEach(history.reversed().prefix(10)) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .font(AppFont.subheadline)
                                    .fontWeight(.semibold)
                                HStack {
                                    Text(entry.date.formatted(.dateTime.month(.abbreviated).day()))
                                    Spacer()
                                    Text(detailLine(for: entry))
                                }
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    onDelete(entry.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Log workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { nameFocused = true }
    }

    private func save() {
        let entry = WorkoutEntry(
            date: date,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            sets: Int(sets) ?? 0,
            reps: Int(reps) ?? 0,
            durationMinutes: Int(minutes) ?? 0
        )
        onLog(entry)
        onClose()
    }

    private func detailLine(for entry: WorkoutEntry) -> String {
        var parts: [String] = []
        if entry.sets > 0 || entry.reps > 0 {
            parts.append("\(entry.sets)×\(entry.reps)")
        }
        if entry.durationMinutes > 0 {
            parts.append("\(entry.durationMinutes) min")
        }
        return parts.joined(separator: " · ")
    }
}
