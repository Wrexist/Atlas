import SwiftUI

/// Resolves an `Exercise` image path to a fetchable URL. The bundled
/// dataset stores paths relative to the upstream
/// `yuhonas/free-exercise-db` repo (e.g. `Bench_Press/0.jpg`); we
/// fetch them lazily from the GitHub raw CDN today and will mirror
/// to our own CDN before any release that exits TestFlight.
///
/// Pulled out of the row view so swapping the host (Vercel proxy,
/// CloudFront, App Group cache) is a one-line change.
enum ExerciseImageResolver {
    /// GitHub raw URL for the upstream dataset's image. Kept as a
    /// `static let` so callers can swap the constant in tests or
    /// behind a feature flag without re-architecting the call site.
    static let baseURL = URL(string: "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises")!

    /// Returns nil for an empty `images` array — caller renders the
    /// SF Symbol placeholder. The dataset always ships two images
    /// per bundled exercise, so this only fires for user-created
    /// custom exercises.
    static func url(for path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return baseURL.appendingPathComponent(path)
    }
}

/// Image view for an exercise. Fades in on load, uses a tinted SF
/// Symbol placeholder on failure, and clips to the requested corner
/// radius. Standalone so the same treatment lives on the row, the
/// detail header, the routine editor, and the active workout card.
struct ExerciseImageView: View {
    let imagePath: String?
    let muscleGroup: MuscleGroup
    var cornerRadius: CGFloat = Spacing.smallCornerRadius
    var contentMode: ContentMode = .fill

    private var url: URL? { ExerciseImageResolver.url(for: imagePath) }

    var body: some View {
        ZStack {
            placeholderTile
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    case .failure, .empty:
                        EmptyView()
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Tinted SF Symbol on a soft surface fill — shown both as the
    /// loading state and as the "image failed / no image" final state.
    /// One look across both branches reads as deliberate, not broken.
    private var placeholderTile: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AppColor.surfaceSecondary.opacity(0.5))
            .overlay {
                Image(systemName: muscleGroup.symbolName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary.opacity(0.7))
            }
    }
}
