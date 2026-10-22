import SwiftUI

struct DoseRowView: View {
    @EnvironmentObject private var store: WatchStore
    let entry: WatchEntry

    private var accessibilityLabel: String {
        let time = entry.scheduledTime.formatted(date: .omitted, time: .shortened)
        let state = entry.completed
            ? String(localized: "taken")
            : String(localized: "not taken")
        return [entry.peptideName, entry.dose, time, state]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var body: some View {
        Button {
            store.toggleEntry(entry)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: entry.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(entry.completed ? WatchPalette.protocolDose : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: entry.completed)
                    .animation(WatchMotion.update, value: entry.completed)

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.abbreviation)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(entry.completed ? .secondary : .primary)
                        .strikethrough(entry.completed, color: .secondary)
                    Text(entry.dose)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Text(entry.scheduledTime, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(entry.completed ? WatchPalette.protocolDose.opacity(0.14) : Color.white.opacity(0.1))
            )
            .animation(WatchMotion.update, value: entry.completed)
            .opacity(store.isSending ? 0.6 : 1)
        }
        .buttonStyle(PressableButtonStyle())
        // Disable while a send is in flight: the row already dims, so
        // leaving it tappable gave no sign a second tap was ignored.
        .disabled(store.isSending)
        // Without this VoiceOver reads the row as four stops, and "taken"
        // is carried only by the checkmark and strikethrough, neither of
        // which it announces.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(entry.completed ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(entry.completed ? "Double tap to mark not taken"
                                           : "Double tap to log this dose")
    }
}
