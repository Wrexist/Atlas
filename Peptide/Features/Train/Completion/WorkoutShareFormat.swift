import Foundation
import CoreGraphics

enum WorkoutShareFormat: String, CaseIterable, Identifiable, Sendable {
    case story, post, reel
    var id: String { rawValue }
    var title: String {
        switch self { case .story: "Story"; case .post: "Post"; case .reel: "Reel" }
    }
    var logicalSize: CGSize { CGSize(width: 360, height: self == .post ? 450 : 640) }
    var pixelSize: CGSize { CGSize(width: 1080, height: self == .post ? 1350 : 1920) }
    var isVideo: Bool { self == .reel }
    var detail: String {
        switch self {
        case .story: "9:16 image · 1080 × 1920"
        case .post: "4:5 image · 1080 × 1350"
        case .reel: "9:16 video · 6 seconds · no audio"
        }
    }
}

enum WorkoutShareStyle: String, CaseIterable, Identifiable, Sendable {
    case summary, highlight
    var id: String { rawValue }
    var title: String { self == .summary ? "Dark summary" : "Exercise highlight" }
}

struct WorkoutShareOptions: Equatable, Hashable, Sendable {
    var format: WorkoutShareFormat = .story
    var style: WorkoutShareStyle = .highlight
    var featuredEntryID: UUID?
    var includeName = true
    var includeDate = false
    var includeVolume = true
}

struct WorkoutShareRenderKey: Hashable {
    let session: WorkoutSession
    let unit: MeasurementUnit
    let options: WorkoutShareOptions
}

/// No workout title, account identifier or precise time in exported filenames.
enum WorkoutShareFiles {
    static func makeURL(video: Bool) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("atlas-workout-\(UUID().uuidString)")
            .appendingPathExtension(video ? "mp4" : "png")
    }

    static func remove(_ url: URL?) {
        guard let url, url.deletingLastPathComponent().standardizedFileURL ==
                FileManager.default.temporaryDirectory.standardizedFileURL,
              url.lastPathComponent.hasPrefix("atlas-workout-"),
              ["png", "mp4"].contains(url.pathExtension) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
