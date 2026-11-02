import SwiftUI

/// One exercise: what it is (eyebrow and title), how it moves (the
/// transparent animation, or the body map), how to do it, your results and
/// its details.
struct ExerciseDetailView: View {
    let exerciseID: String
    @State private var library = ExerciseLibrary.shared
    /// Follows the in-app language picker, so the steps match the UI.
    @Environment(\.locale) private var locale
    /// Step-number circle, scaled with the text so "10" still fits.
    @ScaledMetric(relativeTo: .headline) private var stepNumberWidth: CGFloat = 26
    @State private var loading = true
    @State private var showsTitle = false

    private var exercise: Exercise? {
        library.lookup(id: exerciseID)
    }

    var body: some View {
        ScrollView {
            if let exercise {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header(for: exercise)
                        .sectionAppear(index: 0)
                    ExerciseShowcaseCard(exercise: exercise)
                        .sectionAppear(index: 1)
                    // How to do it sits right under what it trains: below
                    // the history it was a scroll away and read as missing.
                    instructionsSection(for: exercise)
                        .sectionAppear(index: 2)
                    ExerciseHistorySection(exercise: exercise)
                        .sectionAppear(index: 3)
                    detailsSection(for: exercise)
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
        // The big title names the screen; the bar repeats it (truncated)
        // only once that title has scrolled under it.
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > Spacing.xxxxl
        } action: { _, scrolledPast in
            AppAnimation.with(AppAnimation.quick) { showsTitle = scrolledPast }
        }
        .navigationTitle(showsTitle ? exercise?.name ?? "" : "")
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
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(eyebrow(for: exercise))
                .font(AppFont.eyebrow)
                .tracking(1)
                .foregroundStyle(AppColor.textSecondary)
            Text(exercise.name)
                .font(AppFont.scaled(30, weight: .regular, relativeTo: .title1))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.leading)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, Spacing.sm)
    }

    /// "QUADS · BARBELL": the prime mover and the kit, above the name.
    private func eyebrow(for exercise: Exercise) -> String {
        let prime = MuscleInvolvementEngine.rows(for: exercise).first { $0.role == .primary }?.name
        return [prime, exercise.equipmentKind.displayName]
            .compactMap { $0 }
            .joined(separator: " · ")
            .uppercased(with: locale)
    }

    // MARK: - Details

    private func detailsSection(for exercise: Exercise) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Details")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
                          alignment: .leading, spacing: Spacing.md) {
                    ForEach(details(for: exercise), id: \.label) { detail in
                        detailTile(detail)
                    }
                }
            }
        }
    }

    private struct Detail {
        let label: String
        let value: String
        let glyph: AppGlyph
    }

    private func details(for exercise: Exercise) -> [Detail] {
        var details = [Detail(label: String(localized: "exercise.detail.equipment", defaultValue: "Equipment"), value: exercise.equipmentKind.displayName,
                              glyph: exercise.equipmentKind.glyph)]
        let accessories = EquipmentAccessory.allCases.filter { exercise.equipmentAccessories.contains($0) }
        if !accessories.isEmpty {
            details.append(Detail(label: String(localized: "exercise.detail.accessories", defaultValue: "Accessories"),
                                  value: accessories.map(\.displayName).formatted(.list(type: .and)),
                                  glyph: accessories[0].glyph))
        }
        if !exercise.isCustom {
            details.append(Detail(label: String(localized: "exercise.detail.level", defaultValue: "Level"), value: levelLabel(exercise.level),
                                  glyph: .system("figure.run")))
        }
        if let mechanic = exercise.mechanic {
            details.append(Detail(label: String(localized: "exercise.detail.type", defaultValue: "Type"), value: mechanicLabel(mechanic),
                                  glyph: .system("gearshape.fill")))
        }
        if let force = exercise.force {
            details.append(Detail(label: String(localized: "exercise.detail.force", defaultValue: "Force"), value: forceLabel(force),
                                  glyph: .system("arrow.up.right.circle.fill")))
        }
        return details
    }

    private func detailTile(_ detail: Detail) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            GlyphImage(glyph: detail.glyph)
                .foregroundStyle(AppColor.textSecondary)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(detail.label)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                Text(detail.value)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func levelLabel(_ level: Exercise.Level) -> String {
        switch level {
        case .beginner:     return String(localized: "Beginner")
        case .intermediate: return String(localized: "Intermediate")
        case .expert:       return String(localized: "Expert")
        }
    }

    private func mechanicLabel(_ mechanic: Exercise.Mechanic) -> String {
        switch mechanic {
        case .compound:  return String(localized: "exercise.mechanic.compound", defaultValue: "Compound")
        case .isolation: return String(localized: "exercise.mechanic.isolation", defaultValue: "Isolation")
        }
    }

    private func forceLabel(_ force: Exercise.Force) -> String {
        switch force {
        case .push:     return String(localized: "exercise.force.push", defaultValue: "Push")
        case .pull:     return String(localized: "exercise.force.pull", defaultValue: "Pull")
        case .static:   return String(localized: "exercise.force.static", defaultValue: "Static")
        }
    }

    // MARK: - Instructions

    private func instructionsSection(for exercise: Exercise) -> some View {
        let steps = library.steps(for: exercise, locale: locale)
        return GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("How to perform")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                if steps.isEmpty {
                    Text("No instructions provided for this exercise.")
                        .font(AppFont.callout)
                        .foregroundStyle(AppColor.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                                Text("\(index + 1)")
                                    .font(AppFont.chipText)
                                    .monospacedDigit()
                                    .foregroundStyle(AppColor.textPrimary)
                                    .frame(width: stepNumberWidth, height: stepNumberWidth)
                                    .background(Circle().fill(AppColor.surfaceSecondary))
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
