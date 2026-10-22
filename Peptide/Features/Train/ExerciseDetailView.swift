import SwiftUI

/// Shared exercise body map and muscle breakdown, metadata and instructions.
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
                        .sectionAppear(index: 0)
                    // The exercise's visual is its body map: the muscles it
                    // trains, marked on the Atlas figure, front and back.
                    muscleSection(for: exercise)
                        .sectionAppear(index: 1)
                    metadataRow(for: exercise)
                        .sectionAppear(index: 2)
                    ExerciseHistorySection(exercise: exercise)
                        .sectionAppear(index: 3)
                    instructionsSection(for: exercise)
                        .sectionAppear(index: 4)
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
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Library unavailable",
                    message: "We couldn't load the exercise library.",
                    action: .init(title: "Retry", icon: "arrow.clockwise") {
                        Task { await loadLibrary() }
                    }
                )
                .padding(.top, Spacing.xxxxl)
            }
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle(exercise?.name ?? "")
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
        Text(exercise.name)
            .font(AppFont.title)
            .foregroundStyle(AppColor.textPrimary)
            .multilineTextAlignment(.leading)
            .padding(.top, Spacing.sm)
    }

    // MARK: - Metadata pills

    private func metadataRow(for exercise: Exercise) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: Spacing.xs) {
            metadataPill(
                glyph: exercise.equipmentKind.glyph,
                label: exercise.equipmentKind.displayName
            )
            ForEach(EquipmentAccessory.allCases.filter { exercise.equipmentAccessories.contains($0) }) { accessory in
                metadataPill(glyph: accessory.glyph, label: accessory.displayName)
            }
            if !exercise.isCustom {
                metadataPill(
                    glyph: .system("figure.run"),
                    label: levelLabel(exercise.level)
                )
            }
            if let mechanic = exercise.mechanic {
                metadataPill(
                    glyph: .system("gearshape.fill"),
                    label: mechanic.rawValue.capitalized
                )
            }
            if let force = exercise.force {
                metadataPill(
                    glyph: .system("arrow.up.right.circle.fill"),
                    label: force.rawValue.capitalized
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metadataPill(glyph: AppGlyph, label: String) -> some View {
        HStack(spacing: Spacing.xs) {
            GlyphImage(glyph: glyph)
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

                MuscleActivationMap(exercise: exercise)
            }
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

    /// Shaped like the title, muscle card, pills and history card, so the
    /// page doesn't jump when the library lands.
    private var loadingState: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            SkeletonBlock(width: 220, height: 24)
                .padding(.top, Spacing.sm)
            SkeletonBlock(height: 340, cornerRadius: Spacing.cardCornerRadius)
            HStack(spacing: Spacing.sm) {
                SkeletonBlock(width: 80, height: 28, cornerRadius: Spacing.smallCornerRadius)
                SkeletonBlock(width: 96, height: 28, cornerRadius: Spacing.smallCornerRadius)
            }
            SkeletonBlock(height: 140, cornerRadius: Spacing.cardCornerRadius)
        }
        .padding(.horizontal, Spacing.screenPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading exercise")
    }
}

#Preview {
    NavigationStack {
        ExerciseDetailView(exerciseID: "Barbell_Bench_Press_-_Medium_Grip")
    }
    .environment(DataStore())
    .preferredColorScheme(.dark)
}
