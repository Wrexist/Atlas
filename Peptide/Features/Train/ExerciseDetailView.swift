import SwiftUI

/// Shared exercise artwork, metadata, muscle breakdown and instructions.
struct ExerciseDetailView: View {
    let exerciseID: String
    @State private var library = ExerciseLibrary.shared
    @State private var loading = true

    private var exercise: Exercise? {
        library.lookup(id: exerciseID)
    }

    var body: some View {
        ScrollView {
            if let exercise {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header(for: exercise)
                    metadataRow(for: exercise)
                    ExerciseHistorySection(exercise: exercise)
                    muscleSection(for: exercise)
                    instructionsSection(for: exercise)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
            } else if library.isLoaded {
                missingState
            } else if loading {
                // Library hasn't finished loading — don't flash a
                // false "not found" before the async load completes.
                loadingState
            } else {
                VStack(spacing: Spacing.md) {
                    Text("Couldn't load the exercise library.")
                    Button("Retry") { Task { await loadLibrary() } }.minimumHitArea()
                }.padding(Spacing.screenPadding)
            }
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadLibrary() }
    }

    private func loadLibrary() async {
        loading = true
        await library.load()
        loading = false
    }

    // MARK: - Header

    private func header(for exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            exerciseArtwork(for: exercise)
                .frame(height: 240)

            Text(exercise.name)
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.leading)
        }
        .padding(.top, Spacing.sm)
    }

    private func exerciseArtwork(for exercise: Exercise) -> some View {
        ExerciseHeroView(exercise: exercise)
            .padding(Spacing.md)
            .background(AppColor.trainingBackground, in: RoundedRectangle(cornerRadius: Spacing.cardCornerRadius))
    }

    // MARK: - Metadata pills

    private func metadataRow(for exercise: Exercise) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: Spacing.xs) {
            metadataPill(
                icon: exercise.equipmentKind.symbolName,
                label: exercise.equipmentKind.displayName
            )
            metadataPill(
                icon: "figure.run",
                label: levelLabel(exercise.level)
            )
            if let mechanic = exercise.mechanic {
                metadataPill(
                    icon: "gearshape.fill",
                    label: mechanic.rawValue.capitalized
                )
            }
            if let force = exercise.force {
                metadataPill(
                    icon: "arrow.up.right.circle.fill",
                    label: force.rawValue.capitalized
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metadataPill(icon: String, label: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(AppFont.scaled(11, weight: .semibold))
            Text(label)
                .font(AppFont.chipText)
        }
        .foregroundStyle(AppColor.textPrimary)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(AppColor.surfaceSecondary.opacity(0.6))
        )
        .overlay(
            Capsule().stroke(AppColor.glassBorder, lineWidth: 0.5)
        )
    }

    private func levelLabel(_ level: Exercise.Level) -> String {
        switch level {
        case .beginner:     return "Beginner"
        case .intermediate: return "Intermediate"
        case .expert:       return "Expert"
        }
    }

    // MARK: - Muscles

    private func muscleSection(for exercise: Exercise) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Muscles worked")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                MuscleMapView(
                    highlights: MuscleMapView.highlights(for: exercise),
                    primaryColor: AppColor.trainingPrimaryMuscle,
                    secondaryColor: AppColor.trainingSecondaryMuscle
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 280)

                muscleLegend(for: exercise)
            }
        }
    }

    private func muscleLegend(for exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if !exercise.primaryMuscles.isEmpty {
                muscleLegendCluster(
                    title: "Primary",
                    muscles: exercise.primaryMuscles,
                    swatch: AppColor.trainingPrimaryMuscle
                )
            }
            if !exercise.secondaryMuscles.isEmpty {
                muscleLegendCluster(
                    title: "Supporting",
                    muscles: exercise.secondaryMuscles,
                    swatch: AppColor.trainingSecondaryMuscle
                )
            }
        }
    }

    private func muscleLegendCluster(title: String, muscles: [String], swatch: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: 6) {
                Circle()
                    .fill(swatch)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(AppFont.footnote.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
            }
            Text(muscles.map { $0.capitalized }.joined(separator: ", "))
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Instructions

    private func instructionsSection(for exercise: Exercise) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("How to perform")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                if exercise.instructions.isEmpty {
                    Text("No instructions provided for this exercise.")
                        .font(AppFont.callout)
                        .foregroundStyle(AppColor.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                                Text("\(index + 1)")
                                    .font(AppFont.headline)
                                    .foregroundStyle(AppColor.accentPrimary)
                                    .frame(width: 22, alignment: .leading)
                                Text(step)
                                    .font(AppFont.callout)
                                    .foregroundStyle(AppColor.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Missing

    private var missingState: some View {
        EmptyStateView(
            icon: "questionmark.circle",
            title: "Exercise not found",
            message: "We couldn't find this exercise in your library. It may have been removed."
        )
        .padding(.top, Spacing.xxxxl)
    }

    private var loadingState: some View {
        ProgressView()
            .tint(AppColor.accentPrimary)
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.xxxxl)
    }
}

#Preview {
    NavigationStack {
        ExerciseDetailView(exerciseID: "Barbell_Bench_Press_-_Medium_Grip")
    }
    .environment(DataStore())
    .preferredColorScheme(.dark)
}
