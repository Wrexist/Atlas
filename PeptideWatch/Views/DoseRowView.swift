import SwiftUI

struct DoseRowView: View {
    @EnvironmentObject private var store: WatchStore
    let entry: WatchEntry

    private var accessibilityLabel: String {
        let time = entry.scheduledTime.formatted(date: .omitted, time: .shortened)
        let state = entry.completed
            ? String(localized: "taken")
            : String(localized: "not taken")
        return "\(entry.peptideName), \(entry.dose), \(time), \(state)"
    }

    var body: some View {
        Button {
            store.toggleEntry(entry)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: entry.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(entry.completed ? .green : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.abbreviation)
                        .font(.headline)
                        .foregroundStyle(entry.completed ? .secondary : .primary)
                    Text(entry.dose)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(entry.scheduledTime, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .opacity(store.isSending ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        // Disable while a send is in flight — the row already dims to
        // 0.6 opacity, so leaving it tappable gave no feedback that a
        // second tap was being ignored (matches the water buttons).
        .disabled(store.isSending)
        .strikethrough(entry.completed, color: .secondary)
        // Without this VoiceOver reads the row as four separate stops,
        // and "completed" is carried only by the checkmark glyph and the
        // strikethrough — neither of which it announces.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(entry.completed ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(entry.completed ? "Double tap to mark not taken"
                                           : "Double tap to log this dose")
    }
}
