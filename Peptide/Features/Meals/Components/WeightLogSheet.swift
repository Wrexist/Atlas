import SwiftUI

/// Modal sheet that captures a new bodyweight entry. Numeric input field,
/// a date picker that defaults to today, and a recent-entries list with
/// swipe-to-delete so the user can fix typos without leaving the sheet.
struct WeightLogSheet: View {
    let history: [WeightEntry]
    let unit: MeasurementUnit
    let onLog: (Double) -> Void
    let onDelete: (UUID) -> Void
    let onClose: () -> Void

    @State private var input: String = ""
    @State private var date: Date = Date()
    @FocusState private var inputFocused: Bool

    private var canSave: Bool { parsedKg() != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("New entry") {
                    HStack {
                        Text(unit == .metric ? "Weight (kg)" : "Weight (lb)")
                        Spacer()
                        TextField("0", text: $input)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            .focused($inputFocused)
                    }
                    DatePicker("When", selection: $date, in: ...Date(), displayedComponents: .date)
                }

                if !history.isEmpty {
                    Section("Recent entries") {
                        ForEach(history.reversed().prefix(10)) { entry in
                            HStack {
                                Text(entry.date.formatted(.dateTime.month(.abbreviated).day().year()))
                                Spacer()
                                Text(format(entry.kg))
                                    .foregroundStyle(AppColor.textSecondary)
                                    .monospacedDigit()
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
            .navigationTitle("Log weight")
            .navigationBarTitleDisplayMode(.inline)
            .glassFormStyle()
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
        .onAppear { inputFocused = true }
    }

    private func parsedKg() -> Double? {
        let cleaned = input
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        guard let value = Double(cleaned), value > 0 else { return nil }
        switch unit {
        case .metric:   return value
        case .imperial: return value / 2.20462
        }
    }

    private func save() {
        guard let kg = parsedKg() else { return }
        onLog(kg)
        onClose()
    }

    private func format(_ kg: Double) -> String {
        switch unit {
        case .metric:    String(format: "%.1f kg", kg)
        case .imperial:  String(format: "%.1f lb", kg * 2.20462)
        }
    }
}
