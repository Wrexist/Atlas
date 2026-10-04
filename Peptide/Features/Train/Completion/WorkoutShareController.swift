import SwiftUI
import AVKit
import UIKit

struct WorkoutShareExport: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor @Observable
final class WorkoutShareController {
    enum Action { case share, save, preview }
    var exportItem: WorkoutShareExport?
    var player: AVPlayer?
    private(set) var busy = false
    private(set) var savingToPhotos = false
    private(set) var progress: Double = 0
    private(set) var error: String?
    private(set) var photoPermissionDenied = false
    private(set) var notice: String?
    private var task: Task<Void, Never>?
    private var preparedKey: WorkoutShareRenderKey?
    private var preparedURL: URL?
    private var preparedReducedMotion = false
    private let files = WorkoutShareFileOwner()

    func optionsChanged() {
        task?.cancel()
        player?.pause()
        player = nil
        preparedKey = nil
        preparedURL = nil
        notice = nil
        error = nil
        photoPermissionDenied = false
    }

    func cancel() { task?.cancel() }

    func shareFinished(error: Error?) {
        if error != nil { self.error = "Sharing did not finish. Try again. Your saved workout is unchanged." }
    }

    func perform(_ action: Action, summary: WorkoutRecapEngine.Summary,
                 unit: MeasurementUnit, options: WorkoutShareOptions, reduceMotion: Bool) {
        guard !busy else { return }
        busy = true
        error = nil
        notice = nil
        photoPermissionDenied = false
        progress = 0
        player?.pause()
        let key = WorkoutShareRenderKey(session: summary.session, unit: unit, options: options)
        task = Task { @MainActor in
            defer { busy = false; savingToPhotos = false; task = nil }
            do {
                let url: URL
                if preparedKey == key, preparedReducedMotion == reduceMotion, let preparedURL {
                    url = preparedURL
                } else {
                    await Task.yield()
                    try Task.checkCancellation()
                    let image = try WorkoutSocialRenderer.image(summary: summary, unit: unit, options: options)
                    url = WorkoutShareFiles.makeURL(video: options.format.isVideo)
                    files.urls.append(url)
                    if options.format.isVideo {
                        guard let cgImage = image.cgImage else { throw WorkoutMediaError.render }
                        try await WorkoutMediaExporter().video(image: cgImage, to: url, reduceMotion: reduceMotion) { value in
                            await MainActor.run { self.progress = value }
                        }
                    } else {
                        guard let data = image.pngData() else { throw WorkoutMediaError.render }
                        try data.write(to: url, options: .atomic)
                    }
                    try Task.checkCancellation()
                    preparedKey = key
                    preparedReducedMotion = reduceMotion
                    preparedURL = url
                }
                try Task.checkCancellation()
                switch action {
                case .share:
                    exportItem = WorkoutShareExport(url: url)
                case .preview:
                    player = AVPlayer(url: url)
                    player?.play()
                case .save:
                    savingToPhotos = true
                    try await WorkoutPhotoLibrary.save(url: url, video: options.format.isVideo)
                    notice = options.format.isVideo ? "Video saved to Photos" : "Image saved to Photos"
                    Haptics.success()
                    AccessibilityNotification.Announcement(notice ?? "Saved to Photos").post()
                }
            } catch is CancellationError {
                // Cancellation is an ordinary user action, not a failed save.
            } catch {
                photoPermissionDenied = (error as? WorkoutMediaError) == .photoPermission
                self.error = error.localizedDescription
                AccessibilityNotification.Announcement("Could not prepare or save the share file").post()
            }
        }
    }
}

/// Keep deinitialization independent of the UI actor and Observation accessors.
/// The controller owns this object for the full preview/share-sheet lifetime.
private final class WorkoutShareFileOwner {
    var urls: [URL] = []
    deinit { for url in urls { WorkoutShareFiles.remove(url) } }
}
