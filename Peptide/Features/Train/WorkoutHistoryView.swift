import SwiftUI

/// Real history list — replaces the hardcoded "No workouts logged
/// yet" placeholder that persisted forever even after 30 finished
/// workouts (audit Train C2). Reads from SwiftDataRepository and
/// groups by month so the user can scan through their year.
struct WorkoutHistoryView: View {
    @State private var sessions: [WorkoutSession] = []
    @State private var hasLoaded: Bool = false

    var body: some View {
        Group {
            if !hasLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sessions.isEmpty {
                EmptyStateView(
                    icon: "calendar",
                    title: "No workouts logged yet",
                    message: "Once you finish your first session, it'll show up here with PRs and a monthly recap."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .onAppear(perform: reload)
    }

    private var content: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.lg, pinnedViews: [.sectionHeaders]) {
                    ForEach(groupedSessions, id: \.month) { group in
                        Section {
                            VStack(spacing: Spacing.sm) {
                                ForEach(group.sessions) { session in
                                    NavigationLink {
                                        WorkoutSessionDetailView(session: session)
                                    } label: {
                                        row(for: session)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } header: {
                            sectionHeader(group.month)
                        }
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxl)
            }
        }
    }

    private func sectionHeader(_ label: String) -> some View {
        HStack {
            Text(label)
                .font(AppFont.eyebrow)
                .tracking(1.2)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.sm)
        .background(AppColor.background)
    }

    private func row(for session: WorkoutSession) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayDate)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                Text(session.name ?? "Workout")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("\(session.exercises.count) exercises · \(session.completedSetCount) sets")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            if let duration = session.durationLabel {
                Text(duration)
                    .font(AppFont.scaled(13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.accentLight)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .stroke(AppColor.glassBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Grouping

    private struct MonthGroup: Hashable {
        let month: String
        let sessions: [WorkoutSession]
    }

    private var groupedSessions: [MonthGroup] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let dict = Dictionary(grouping: sessions) { session in
            formatter.string(from: session.finishedAt ?? session.startedAt)
        }
        // Newest month first.
        return dict
            .map { MonthGroup(month: $0.key, sessions: $0.value.sorted { ($0.finishedAt ?? $0.startedAt) > ($1.finishedAt ?? $1.startedAt) }) }
            .sorted { lhs, rhs in
                (lhs.sessions.first?.finishedAt ?? lhs.sessions.first?.startedAt ?? .distantPast)
                    > (rhs.sessions.first?.finishedAt ?? rhs.sessions.first?.startedAt ?? .distantPast)
            }
    }

    private func reload() {
        sessions = SwiftDataRepository.shared.loadWorkoutSessions()
            .filter { $0.finishedAt != nil }
        hasLoaded = true
    }
}

private extension WorkoutSession {
    /// "Mon, Aug 12" — local-relative date label for the row header.
    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: finishedAt ?? startedAt)
    }

    /// "42m" / "1h 12m" — nil for sessions without a finishedAt
    /// (shouldn't happen for entries in this view since we filter,
    /// but defensive).
    var durationLabel: String? {
        guard let finished = finishedAt else { return nil }
        let interval = finished.timeIntervalSince(startedAt)
        guard interval > 0 else { return nil }
        let totalMinutes = Int(interval / 60)
        if totalMinutes < 60 { return "\(totalMinutes)m" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}
