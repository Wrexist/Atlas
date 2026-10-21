import SwiftUI

/// Sheet that lets the user browse exercises by touching the body: tap a
/// muscle, the whole group lights up with how many exercises train it, and
/// confirming applies that group as the library filter.
struct BodyMusclePicker: View {
    @Binding var selection: MuscleGroup?
    var equipment: EquipmentKind? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var picked: MuscleGroup?
    @State private var tapped: AnatomicalMuscle?
    @State private var library = ExerciseLibrary.shared

    private static let pickable: [MuscleGroup] = [.chest, .back, .shoulders, .arms, .legs, .glutes, .core]

    private var highlights: [AnatomicalMuscle: MuscleHighlight] {
        guard let picked else { return [:] }
        return MuscleInvolvementEngine.muscles(in: picked).reduce(into: [:]) { map, muscle in
            map[muscle] = tapped == nil || muscle == tapped ? .primary : .secondary
        }
    }

    private var exerciseCount: Int {
        picked.map { library.filter(muscleGroup: $0, equipment: equipment).count } ?? 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                StagedMuscleMap(
                    highlights: highlights,
                    primaryColor: AppColor.accentPrimary,
                    secondaryColor: AppColor.accentPrimary.opacity(0.55),
                    onIdentify: { pick($0) },
                    selectedMuscle: tapped
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                groupChips
                caption
                confirmButton
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.lg)
            .background(AppColor.background)
            .navigationTitle("Pick on body")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if selection != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear") {
                            selection = nil
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear { picked = selection }
        .task { await library.load() }
    }

    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(Self.pickable) { group in
                    Button { pick(group) } label: {
                        Text(group.displayName)
                            .font(AppFont.chipText)
                            .foregroundStyle(picked == group ? AppColor.onAccent : AppColor.textPrimary)
                            .padding(.horizontal, Spacing.md)
                            .frame(minHeight: Spacing.minimumHitTarget)
                            .background(Capsule().fill(picked == group ? AppColor.accentPrimary : AppColor.surfaceSecondary))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(picked == group ? .isSelected : [])
                }
            }
        }
    }

    private var caption: some View {
        Text(picked.map { muscle -> LocalizedStringKey in "\(muscle.displayName) · ^[\(exerciseCount) exercise](inflect: true)" } ?? "Tap a muscle to see what trains it")
            .font(AppFont.headline)
            .foregroundStyle(picked == nil ? AppColor.textSecondary : AppColor.textPrimary)
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : AppAnimation.springSnappy, value: picked)
    }

    private var confirmButton: some View {
        Button {
            selection = picked
            Haptics.impact()
            dismiss()
        } label: {
            Text(picked == nil ? "Choose a muscle" : "Show ^[\(exerciseCount) exercise](inflect: true)")
                .font(AppFont.headline)
                .frame(maxWidth: .infinity, minHeight: Spacing.minimumHitTarget)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColor.accentPrimary)
        .disabled(picked == nil)
        .accessibilityIdentifier("body-picker-confirm")
    }

    private func pick(_ muscle: AnatomicalMuscle) {
        let group = MuscleInvolvementEngine.group(for: muscle)
        Haptics.selection()
        withAnimation(reduceMotion ? nil : AppAnimation.springSnappy) {
            tapped = muscle
            picked = group
        }
    }

    private func pick(_ group: MuscleGroup) {
        Haptics.selection()
        withAnimation(reduceMotion ? nil : AppAnimation.springSnappy) {
            tapped = nil
            picked = group
        }
    }
}

#Preview {
    BodyMusclePicker(selection: .constant(.chest))
        .preferredColorScheme(.dark)
}
