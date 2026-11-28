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
                                    if let title = header(at: index) {
                                        groupHeader(title, isBest: index == 0)
                                    } else {
                                        Divider().padding(.leading, ExerciseRow.tileSize + Spacing.md)
                                    }
                                    option(row.exercise)
                                        .accessibilityIdentifier("swap-option-\(index)")
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

    private func option(_ exercise: Exercise) -> some View {
        Button {
            Haptics.selection()
            onPick(exercise)
            dismiss()
        } label: {
            ExerciseRow(exercise: exercise, showsChevron: false)
                .padding(.vertical, Spacing.xxs)
                .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityHint(Text("Swaps it in"))
    }

    /// The best match stands alone; the rest are grouped by how close they
    /// are, one label per group.
    private func header(at index: Int) -> LocalizedStringKey? {
        if index == 0 { return "Best match" }
        let match = rows[index].alternative.match
        guard index == 1 || rows[index - 1].alternative.match != match else { return nil }
        return match.title
    }

    private func groupHeader(_ title: LocalizedStringKey, isBest: Bool) -> some View {
        Text(title)
            .font(AppFont.eyebrow)
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(isBest ? AppColor.accentPrimary : AppColor.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, isBest ? 0 : Spacing.lg)
            .padding(.bottom, Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }
}

extension SessionBuilderEngine.Alternative.Match {
    /// The group label shared by the swap sheet and the workout's swap menu.
    var title: LocalizedStringKey {
        switch self {
        case .sameMovement: return "Same movement"
        case .otherAngle: return "Other angle"
        case .similarMovement: return "Similar movement"
        case .sameMuscle: return "Same muscle"
        }
    }
}
