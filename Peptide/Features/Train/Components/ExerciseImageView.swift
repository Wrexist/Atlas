import SwiftUI

/// The same offline visual on picker rows, routines and workout strips:
/// 3D art when it exists, else the bundled start-position photo, else the
/// muscle map. Always resolved by exercise identity, never by a similar name.
struct ExerciseImageView: View {
    let exercise: Exercise?
    var cornerRadius: CGFloat = Spacing.smallCornerRadius
    var showsPhotos = true

    private var rendersPhoto: Bool {
        guard let exercise, showsPhotos else { return false }
        return ExerciseVisualAssets.poster(for: exercise.id) == nil && ExercisePhotos.thumbnail(for: exercise.id) != nil
    }

    private var showsMuscleMap: Bool {
        guard let exercise else { return false }
        return ExerciseVisualAssets.poster(for: exercise.id) == nil && !rendersPhoto
    }

    var body: some View {
        ExerciseHeroView(exercise: exercise, compact: true, showsPhotos: showsPhotos)
            .padding(rendersPhoto ? 0 : Spacing.xs)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .background(AppColor.trainingBackground)
            .overlay(alignment: .bottomTrailing) {
                if let exercise, showsMuscleMap {
                    Image(systemName: exercise.equipmentKind.symbolName)
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(3)
                        .background(AppColor.trainingPanel, in: Circle())
                        .padding(2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}
