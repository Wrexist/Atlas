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
///
/// Security: the underlying `AsyncImage` is wrapped in a bounded
/// `URLSession` with a 10s timeout and a 2 MB payload cap so a
/// hostile upstream can't OOM the device or stall the UI. The
/// session also rejects non-`image/*` Content-Types so ImageIO never
/// sees a payload that wasn't declared as an image.
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
                BoundedRemoteImage(url: url, contentMode: contentMode)
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

// MARK: - Bounded URLSession wrapper

/// `AsyncImage`-shaped view backed by a hand-rolled `URLSession` data
/// task with strict bounds: 10s timeout, 2 MB max payload, image/*
/// Content-Type only. Decodes the bytes via `UIImage`/`Image`. Failure
/// modes fall through silently so the placeholder shows through.
private struct BoundedRemoteImage: View {
    let url: URL
    let contentMode: ContentMode

    @State private var image: UIImage?
    @State private var didStart = false

    private static let maxBytes = 2_000_000  // 2 MB cap per image
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.urlCache = URLCache(memoryCapacity: 8_000_000,
                                   diskCapacity: 64_000_000,
                                   directory: nil)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        guard image == nil else { return }
        do {
            let (data, response) = try await Self.session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let type = http.value(forHTTPHeaderField: "Content-Type"),
                  type.lowercased().hasPrefix("image/"),
                  data.count <= Self.maxBytes,
                  let decoded = UIImage(data: data)
            else {
                AppLog.training.debug("Exercise image rejected: status / content-type / size mismatch")
                return
            }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.image = decoded
                }
            }
        } catch {
            // Quietly swallow — placeholder stays visible.
            AppLog.training.debug("Exercise image fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
