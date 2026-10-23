import Foundation
import CoreGraphics

/// How a share canvas arranges its content blocks. Every canvas composes
/// the same blocks for every format; only the arrangement changes, so a
/// square or landscape export is a real layout rather than a scaled story.
enum ShareLayout: Sendable {
    /// 9:16 — one generous column, top to bottom.
    case tall
    /// Near-square — the same column with tighter spacing and smaller hero.
    case compact
    /// Landscape — hero on the left, stats on the right.
    case wide
}

/// Image share formats. Pixel sizes are what the destination expects, so a
/// file never needs re-cropping after export.
enum ShareFormat: String, CaseIterable, Identifiable, Sendable {
    /// Instagram / Snapchat Stories.
    case story
    /// Feed posts.
    case square
    /// Link previews (Open Graph) and X.
    case landscape

    var id: String { rawValue }

    var pixelSize: CGSize {
        switch self {
        case .story: CGSize(width: 1080, height: 1920)
        case .square: CGSize(width: 1080, height: 1080)
        case .landscape: CGSize(width: 1200, height: 630)
        }
    }

    var layout: ShareLayout {
        switch self {
        case .story: .tall
        case .square: .compact
        case .landscape: .wide
        }
    }

    var title: String {
        switch self {
        case .story: String(localized: "Story")
        case .square: String(localized: "Square")
        case .landscape: String(localized: "Wide")
        }
    }

    var detail: String {
        switch self {
        case .story: String(localized: "9:16 image · 1080 × 1920 · Stories")
        case .square: String(localized: "1:1 image · 1080 × 1080 · Feed posts")
        case .landscape: String(localized: "1.91:1 image · 1200 × 630 · Link previews and X")
        }
    }
}

/// Anything a `ShareFormatPicker` can offer: a name and the canvas shape
/// its glyph draws.
protocol ShareFormatDescribing: Hashable, Identifiable {
    var title: String { get }
    var detail: String { get }
    /// Width over height of the exported canvas.
    var aspectRatio: CGFloat { get }
    /// SF Symbol drawn inside the glyph, e.g. a play mark for video.
    var glyphSymbol: String? { get }
}

extension ShareFormat: ShareFormatDescribing {
    var aspectRatio: CGFloat { pixelSize.width / pixelSize.height }
    var glyphSymbol: String? { nil }
}

/// Remembers the last format picked on each share surface so the next share
/// opens where the user left off. A stored value that no longer names a case
/// (a format removed in a later release) falls back to the default.
enum ShareFormatMemory {
    static let cycleCardKey = "share.format.cycleCard"
    static let workoutKey = "share.format.workout"

    static func load<Format: RawRepresentable>(
        _ key: String,
        default fallback: Format,
        from defaults: UserDefaults = .standard
    ) -> Format where Format.RawValue == String {
        defaults.string(forKey: key).flatMap(Format.init(rawValue:)) ?? fallback
    }

    static func save<Format: RawRepresentable>(
        _ format: Format,
        _ key: String,
        to defaults: UserDefaults = .standard
    ) where Format.RawValue == String {
        defaults.set(format.rawValue, forKey: key)
    }
}
