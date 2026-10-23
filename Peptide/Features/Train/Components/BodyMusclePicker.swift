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
                            .background(Capsule().fill(picked == group ? AppColor.accentFill : AppColor.surfaceSecondary))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(picked == group ? .isSelected : [])
                }
            }
        }
    }

    private var caption: some View {
        captionText
            .font(AppFont.headline)
            .foregroundStyle(picked == nil ? AppColor.textSecondary : AppColor.textPrimary)
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : AppAnimation.springSnappy, value: picked)
    }

    private var captionText: Text {
        guard let picked else { return Text("Tap a muscle to see what trains it") }
        return Text("\(picked.displayName) · ^[\(exerciseCount) exercise](inflect: true)")
    }

    private var confirmTitle: LocalizedStringKey {
        if picked == nil { return "Choose a muscle" }
        if exerciseCount == 0 { return "No exercises with this equipment" }
        return "Show ^[\(exerciseCount) exercise](inflect: true)"
    }

    private var confirmButton: some View {
        PrimaryCTAButton(title: confirmTitle, shape: .rounded) {
            selection = picked
            Haptics.impact()
            dismiss()
        }
        .disabled(picked == nil || exerciseCount == 0)
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
