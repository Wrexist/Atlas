import Foundation
import CoreGraphics

enum WorkoutShareFormat: String, CaseIterable, Identifiable, Sendable {
    case story, post, square, landscape, reel
    var id: String { rawValue }
    var title: String {
        switch self {
        case .story: String(localized: "Story")
        case .post: String(localized: "Post")
        case .square: ShareFormat.square.title
        case .landscape: ShareFormat.landscape.title
        case .reel: String(localized: "Reel")
        }
    }
    var pixelSize: CGSize {
        switch self {
        case .story, .reel: ShareFormat.story.pixelSize
        case .post: CGSize(width: 1080, height: 1350)
        case .square: ShareFormat.square.pixelSize
        case .landscape: ShareFormat.landscape.pixelSize
        }
    }
    /// The canvases are authored in points at the size a phone shows them,
    /// so a wider canvas renders at a lower scale to keep its type in step
    /// with the 360pt-wide portrait formats.
    var renderScale: CGFloat { self == .landscape ? 2.5 : 3 }
    var logicalSize: CGSize {
        CGSize(width: pixelSize.width / renderScale, height: pixelSize.height / renderScale)
    }
    var layout: ShareLayout {
        switch self {
        case .story, .reel: .tall
        case .post, .square: .compact
        case .landscape: .wide
        }
    }
    var isVideo: Bool { self == .reel }
    var detail: String {
        switch self {
        case .story: ShareFormat.story.detail
        case .post: String(localized: "4:5 image · 1080 × 1350")
        case .square: ShareFormat.square.detail
        case .landscape: ShareFormat.landscape.detail
        case .reel: String(localized: "9:16 video · 6 seconds · no audio")
        }
    }
}

extension WorkoutShareFormat: ShareFormatDescribing {
    var aspectRatio: CGFloat { pixelSize.width / pixelSize.height }
    var glyphSymbol: String? { isVideo ? "play.fill" : nil }
}

enum WorkoutShareStyle: String, CaseIterable, Identifiable, Sendable {
    case summary, highlight
    var id: String { rawValue }
    var title: String { self == .summary ? String(localized: "Dark summary") : String(localized: "Exercise highlight") }
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
