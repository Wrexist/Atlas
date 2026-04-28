import SwiftUI

struct DoseListView: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        NavigationStack {
            Group {
                if store.watchData.todayEntries.isEmpty {
                    emptyState
                } else {
                    List(store.watchData.todayEntries) { entry in
                        DoseRowView(entry: entry)
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.carousel)
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                complianceRing
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            Text("No doses today")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var complianceRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: store.watchData.compliance)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(store.watchData.completedToday)/\(store.watchData.totalToday)")
                .font(.system(size: 9, weight: .semibold))
        }
        .frame(width: 28, height: 28)
    }
}
