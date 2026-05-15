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
            } else {
                missingState
            }
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { library.load() }
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
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
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
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Muscles worked")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                if !exercise.primaryMuscles.isEmpty {
                    musclePillCluster(
                        title: "Primary",
                        muscles: exercise.primaryMuscles,
                        accent: AppColor.accentPrimary
                    )
                }

                if !exercise.secondaryMuscles.isEmpty {
                    musclePillCluster(
                        title: "Secondary",
                        muscles: exercise.secondaryMuscles,
                        accent: AppColor.textSecondary
                    )
                }
            }
        }
    }

    private func musclePillCluster(title: String, muscles: [String], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textSecondary)
                .textCase(.uppercase)

            FlowChipLayout(spacing: Spacing.xs, lineSpacing: Spacing.xs) {
                ForEach(muscles, id: \.self) { muscle in
                    Text(muscle.capitalized)
                        .font(AppFont.chipText)
                        .foregroundStyle(AppColor.textPrimary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(accent.opacity(0.18))
                        )
                        .overlay(
                            Capsule().stroke(accent.opacity(0.3), lineWidth: 0.5)
                        )
                }
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
}

// MARK: - FlowChipLayout

/// Lightweight flow layout for chip clusters — wraps to the next
/// line when an element doesn't fit horizontally. Used here instead
/// of HStack so muscle pills with long labels (e.g. "middle back")
/// don't push the row off-screen on small devices.
struct FlowChipLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = layoutRows(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { acc, row in acc + row.height + lineSpacing } - lineSpacing
        return CGSize(
            width: maxWidth.isFinite ? maxWidth : rows.map(\.width).max() ?? 0,
            height: max(0, height)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = layoutRows(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int]
        var width: CGFloat
        var height: CGFloat
    }

    private func layoutRows(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row(indices: [], width: 0, height: 0)

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let projected = current.width + (current.indices.isEmpty ? 0 : spacing) + size.width
            if projected > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row(indices: [], width: 0, height: 0)
            }
            current.indices.append(index)
            current.width += (current.indices.count == 1 ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

#Preview {
    NavigationStack {
        ExerciseDetailView(exerciseID: "Barbell_Bench_Press")
    }
    .preferredColorScheme(.dark)
}
