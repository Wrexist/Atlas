import SwiftUI

/// Log a meal in words instead of a photo: "two eggs, a cheese sandwich
/// and a glass of milk". The keyboard's microphone covers dictation, so
/// speaking it is the same field. Lands on the same review as a photo.
struct MealDescriptionSheet: View {
    @Binding var text: String
    let onAnalyse: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("2 eggs, a cheese sandwich and a glass of milk", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused)
                        .submitLabel(.done)
                } footer: {
                    Text("Amounts help (\"a big bowl\", \"200 g\"). Tap the microphone on the keyboard to dictate.")
                }
            }
            .navigationTitle("Describe your meal")
            .navigationBarTitleDisplayMode(.inline)
            .glassFormStyle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Analyse") { onAnalyse(String(trimmed.prefix(500))) }
                        .disabled(trimmed.count < 2)
                }
            }
            .onAppear { focused = true }
        }
    }
}
