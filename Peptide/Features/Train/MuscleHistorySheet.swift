import SwiftUI

/// Tap-to-inspect sheet for the muscle map. When the user taps a muscle on
/// the figure, this lists the exercises they've actually logged for that
/// head over the last month — newest first — in the app's own card style.
struct MuscleHistorySheet: View {
    let muscle: AnatomicalMuscle
    let history: [MuscleExerciseHistory]
    var periodLabel: String = "Last 30 days"
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
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(session.name ?? "Workout")
                                                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                                        .font(AppFont.caption)
                                                        .foregroundStyle(AppColor.textSecondary)
                                                }
                                                .padding(.vertical, Spacing.sm)
                                            }
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
            .navigationTitle(muscle.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.accentPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var subtitle: some View {
        Text(history.isEmpty
             ? periodLabel
             : "\(totalSets) \(totalSets == 1 ? "set" : "sets") - \(periodLabel.lowercased())")
            .font(AppFont.subheadline)
            .foregroundStyle(AppColor.textSecondary)
    }

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: Spacing.sm) {
                Image(systemName: "dumbbell")
                    .font(.title2)
                    .foregroundStyle(AppColor.textSecondary)
                Text("No logged work for \(muscle.displayName.lowercased()) for this period.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
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
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: Spacing.sm)
                Text("\(item.sets) \(item.sets == 1 ? "set" : "sets")")
                    .font(AppFont.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
