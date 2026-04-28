import SwiftUI

struct DoseRowView: View {
    @EnvironmentObject private var store: WatchStore
    let entry: WatchEntry

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

                Text(entry.scheduledTime)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .opacity(store.isSending ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .strikethrough(entry.completed, color: .secondary)
    }
}
