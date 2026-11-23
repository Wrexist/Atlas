import SwiftUI

/// Tap-to-inspect sheet for the muscle map. When the user taps a muscle on
/// the figure, this lists the exercises they've actually logged for that
/// head over the last month — newest first — in the app's own card style.
struct MuscleHistorySheet: View {
    let muscle: AnatomicalMuscle
    let history: [MuscleExerciseHistory]
    var periodLabel: String = String(localized: "Last 30 days")
    var sessions: [WorkoutSession] = []
    @Environment(\.dismiss) private var dismiss

    private var totalSets: Int { history.reduce(0) { $0 + $1.sets } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    subtitle
                    if history.isEmpty {
                        emptyState
                    } else {
                        ForEach(history) { item in
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                row(item)
                                let contributing = sessions.filter {
                                    item.sessionIDs.contains($0.id) && !$0.isActive
                                }.sorted { $0.startedAt > $1.startedAt }
                                if !contributing.isEmpty {
                                    DisclosureGroup("Contributing workouts (\(contributing.count))") {
                                        ForEach(contributing) { session in
                                            NavigationLink {
                                                WorkoutSessionDetailView(session: session)
                                            } label: {
                                                HStack {
                                                    VStack(alignment: .leading, spacing: Spacing.xs) {
                                                        Text(session.displayName)
                                                            .foregroundStyle(AppColor.textPrimary)
                                                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                                            .font(AppFont.caption2)
                                                            .foregroundStyle(AppColor.textSecondary)
                                                    }
                                                    Spacer(minLength: Spacing.sm)
                                                    Image(systemName: "chevron.right")
                                                        .font(AppFont.scaled(13, weight: .semibold))
                                                        .foregroundStyle(AppColor.textTertiary)
                                                        .accessibilityHidden(true)
                                                }
                                                .padding(.vertical, Spacing.sm)
                                                .contentShape(Rectangle())
                                            }
                                            // A row, not an action: the accent stays on actions.
                                            .buttonStyle(ScalePressStyle(pressedScale: 0.98))
                                        }
                                    }
                                    .font(AppFont.subheadline)
                                }
                            }
                        }
                    }
                }
                .padding(Spacing.screenPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle(muscle.regionName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("muscle-history-done")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.accentPrimary)
                }
            }
        }
        .environment(\.dismissWorkoutHistorySheet, { dismiss() })
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var subtitle: some View {
        Group {
            if history.isEmpty {
                Text(periodLabel)
            } else {
                Text("^[\(totalSets) set](inflect: true) · \(periodLabel.lowercased())")
            }
        }
        .font(AppFont.subheadline)
        .foregroundStyle(AppColor.textSecondary)
    }

    private var emptyState: some View {
        GlassCard {
            EmptyStateView(
                icon: "dumbbell",
                title: "Nothing logged yet",
                message: "No logged work for \(muscle.displayName.lowercased()) for this period.",
                style: .compact
            )
        }
    }

    private func row(_ item: MuscleExerciseHistory) -> some View {
        GlassCard {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(item.lastPerformed.formatted(.relative(presentation: .named)))
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: Spacing.sm)
                Text("^[\(item.sets) set](inflect: true)")
                    .font(AppFont.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
