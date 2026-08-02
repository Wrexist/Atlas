import SwiftUI

/// Full-screen drill-in for a single exercise. Header carousel, raw
/// metadata pills (force, mechanic, level), muscle breakdown, and
/// step-by-step instructions. The "Add to workout" CTA is disabled
/// until the active-workout screen lands in a follow-on commit; it
/// appears in the layout so the surface design is final at this
/// stage.
struct ExerciseDetailView: View {
    let exerciseID: String
    @State private var library = ExerciseLibrary.shared

    private var exercise: Exercise? {
        library.lookup(id: exerciseID)
    }

    var body: some View {
        ScrollView {
            if let exercise {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header(for: exercise)
                    metadataRow(for: exercise)
                    muscleSection(for: exercise)
                    instructionsSection(for: exercise)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
            } else if library.isLoaded {
                missingState
            } else {
                // Library hasn't finished loading — don't flash a
                // false "not found" before the async load completes.
                loadingState
            }
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await library.load() }
    }

    // MARK: - Header

    private func header(for exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            imageCarousel(for: exercise)
                .frame(height: 240)

            Text(exercise.name)
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.leading)
        }
        .padding(.top, Spacing.sm)
    }

    @ViewBuilder
    private func imageCarousel(for exercise: Exercise) -> some View {
        if exercise.images.isEmpty {
            ExerciseImageView(
                imagePath: nil,
                muscleGroup: exercise.muscleGroup,
                cornerRadius: Spacing.cardCornerRadius,
                contentMode: .fit
            )
        } else if exercise.images.count == 1 {
            ExerciseImageView(
                imagePath: exercise.images[0],
                muscleGroup: exercise.muscleGroup,
                cornerRadius: Spacing.cardCornerRadius
            )
        } else {
            // Two images per bundled exercise — start + end position.
            // TabView paging gives a swipe affordance that beats
            // stacking the frames in a vertical strip.
            TabView {
                ForEach(Array(exercise.images.enumerated()), id: \.offset) { _, path in
                    ExerciseImageView(
                        imagePath: path,
                        muscleGroup: exercise.muscleGroup,
                        cornerRadius: Spacing.cardCornerRadius
                    )
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }

    // MARK: - Metadata pills

    private func metadataRow(for exercise: Exercise) -> some View {
        HStack(spacing: Spacing.xs) {
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

                MuscleMapView(highlights: MuscleMapView.highlights(for: exercise))
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
                    swatch: AppColor.negative
                )
            }
            if !exercise.secondaryMuscles.isEmpty {
                muscleLegendCluster(
                    title: "Secondary",
                    muscles: exercise.secondaryMuscles,
                    swatch: AppColor.belowRange
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
        ExerciseDetailView(exerciseID: "Barbell_Bench_Press")
    }
    .preferredColorScheme(.dark)
}
