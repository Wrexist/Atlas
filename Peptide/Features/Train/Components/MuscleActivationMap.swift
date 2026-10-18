import SwiftUI

/// Exercise-detail muscle panel: the igniting body map plus a ranked list of
/// every region the lift trains, each with an involvement bar. Tapping a row
/// or a muscle on the figure focuses that region; tapping it again clears.
struct MuscleActivationMap: View {
    let exercise: Exercise

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focused: MuscleInvolvementEngine.Row?
    @State private var barsFilled = false

    private var highlights: [AnatomicalMuscle: MuscleHighlight] {
        MuscleMapView.highlights(for: exercise)
    }

    private var rows: [MuscleInvolvementEngine.Row] {
        MuscleInvolvementEngine.rows(for: exercise)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            StagedMuscleMap(
                highlights: focused.map { MuscleInvolvementEngine.focus(highlights, on: $0) } ?? highlights,
                onIdentify: { muscle in toggle(rows.first { $0.muscles.contains(muscle) }) },
                selectedMuscle: focused?.muscles.first
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: 280)

            focusCaption

            if !rows.isEmpty {
                VStack(spacing: Spacing.xs) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        rowButton(row, index: index)
                    }
                }
            }
        }
        .onAppear { barsFilled = reduceMotion }
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: AppAnimation.muscleStageDelay)
            barsFilled = true
        }
    }

    private var focusCaption: some View {
        Text(focused.map { "\($0.name) · \($0.role.rawValue.lowercased()) mover" }
             ?? "Tap a muscle to focus it")
            .font(AppFont.footnote.weight(.semibold))
            .foregroundStyle(focused == nil ? AppColor.textTertiary : AppColor.textPrimary)
            .frame(maxWidth: .infinity)
            .contentTransition(.opacity)
            .animation(reduceMotion ? nil : AppAnimation.fadeIn, value: focused)
    }

    private func rowButton(_ row: MuscleInvolvementEngine.Row, index: Int) -> some View {
        let isDimmed = focused != nil && focused != row
        let tint = row.role == .primary ? AppColor.trainingPrimaryMuscle : AppColor.trainingSecondaryMuscle
        return Button { toggle(row) } label: {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack {
                    Circle().fill(tint).frame(width: 8, height: 8)
                    Text(row.name)
                        .font(AppFont.callout.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text(row.role.rawValue)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                involvementBar(share: row.share, tint: tint, index: index)
            }
            .frame(minHeight: Spacing.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isDimmed ? 0.4 : 1)
        .animation(reduceMotion ? nil : AppAnimation.springSnappy, value: focused)
        .accessibilityLabel("\(row.name), \(row.role.rawValue), \(Int(row.share * 100)) percent involvement")
        .accessibilityAddTraits(focused == row ? .isSelected : [])
    }

    private func involvementBar(share: Double, tint: Color, index: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(AppColor.surfaceSecondary)
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * (barsFilled ? share : 0))
            }
        }
        .frame(height: 6)
        .animation(reduceMotion ? nil : AppAnimation.staggered(index: index), value: barsFilled)
        .accessibilityHidden(true)
    }

    private func toggle(_ row: MuscleInvolvementEngine.Row?) {
        let next = row == focused ? nil : row
        guard next != focused else { return }
        Haptics.selection()
        if reduceMotion {
            focused = next
        } else {
            withAnimation(AppAnimation.springSnappy) { focused = next }
        }
    }
}

#Preview {
    ScrollView {
        if let exercise = ExerciseLibrary.shared.lookup(id: "Barbell_Bench_Press_-_Medium_Grip") {
            MuscleActivationMap(exercise: exercise).padding()
        }
    }
    .background(AppColor.background)
    .task { await ExerciseLibrary.shared.load() }
    .preferredColorScheme(.dark)
}
