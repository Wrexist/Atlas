import SwiftUI

/// The next-best exercises for one the user wants out, best first: lifts
/// doing the same movement on the same muscle, then ones that only share
/// the muscle. Picking one hands it back and closes the sheet. Used by the
/// session builder's swipe and the active workout's swap button.
struct ExerciseSwapSheet: View {
    let currentName: String
    let alternatives: [SessionBuilderEngine.Alternative]
    let onPick: (Exercise) -> Void

    @State private var library = ExerciseLibrary.shared
    @Environment(\.dismiss) private var dismiss

    private var rows: [(alternative: SessionBuilderEngine.Alternative, exercise: Exercise)] {
        alternatives.compactMap { alternative in
            library.lookup(id: alternative.id).map { (alternative, $0) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Instead of \(currentName)")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                    if rows.isEmpty {
                        GlassCard {
                            EmptyStateView(
                                icon: "arrow.triangle.2.circlepath",
                                title: "No swap with your equipment",
                                message: "Tick more equipment to see other exercises for this muscle.",
                                style: .compact
                            )
                        }
                    } else {
                        GlassCard(padding: Spacing.md) {
                            VStack(spacing: 0) {
                                ForEach(Array(rows.enumerated()), id: \.element.exercise.id) { index, row in
                                    if index > 0 {
                                        Divider().padding(.leading, ExerciseRow.tileSize + Spacing.md)
                                    }
                                    option(row.exercise, alternative: row.alternative, isBest: index == 0)
                                }
                            }
                        }
                    }
                }
                .padding(Spacing.screenPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("Swap exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.accentPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func option(_ exercise: Exercise, alternative: SessionBuilderEngine.Alternative, isBest: Bool) -> some View {
        Button {
            Haptics.selection()
            onPick(exercise)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(reason(alternative, isBest: isBest))
                    .font(AppFont.eyebrow)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(isBest ? AppColor.accentPrimary : AppColor.textTertiary)
                    .padding(.leading, ExerciseRow.tileSize + Spacing.md)
                ExerciseRow(exercise: exercise, showsChevron: false)
            }
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Swaps it in"))
    }

    private func reason(_ alternative: SessionBuilderEngine.Alternative, isBest: Bool) -> LocalizedStringKey {
        switch (isBest, alternative.isSameMovement) {
        case (true, _): return "Best match"
        case (false, true): return "Same movement"
        case (false, false): return "Same muscle"
        }
    }
}
