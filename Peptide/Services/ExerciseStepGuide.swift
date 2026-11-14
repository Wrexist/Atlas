import CoreGraphics
import Foundation
import OSLog

/// The reviewed step pictures for an exercise: two or three moments of its
/// rendered clip (start, peak, sometimes the middle; one for a static
/// hold), each with a short title and one form cue. Bundled in
/// `exercise-steps.json`.
///
/// Only exercises whose clip passed a frame-by-frame technique review are
/// listed. The list doubles as the gate for the clip itself: an exercise
/// without a guide shows neither pictures nor video, only the muscle map,
/// because a clip that failed review would teach the wrong movement.
enum ExerciseStepGuide {
    struct Step: Equatable, Sendable {
        /// Seconds into the clip.
        let time: Double
        let title: String
        let cue: String
    }

    struct Guide: Equatable, Sendable {
        /// The part of each frame to show, in unit coordinates (origin top
        /// left), 4:5 like the clip, so the figure fills the picture.
        let crop: CGRect
        let steps: [Step]
    }

    /// The guide in `locale`'s language (Swedish or English); nil when the
    /// exercise has none.
    static func guide(for exerciseID: String, locale: Locale) -> Guide? {
        guard let entry = entries[exerciseID] else { return nil }
        let swedish = locale.language.languageCode?.identifier == "sv"
        return Guide(
            crop: CGRect(x: entry.crop[0], y: entry.crop[1], width: entry.crop[2], height: entry.crop[3]),
            steps: entry.steps.map { step in
                let text = swedish ? step.sv : step.en
                return Step(time: step.time, title: text.title, cue: text.cue)
            }
        )
    }

    static func hasGuide(for exerciseID: String) -> Bool {
        entries[exerciseID] != nil
    }

    struct Entry: Decodable, Sendable {
        let crop: [Double]
        let steps: [EntryStep]
    }

    struct EntryStep: Decodable, Sendable {
        let time: Double
        let en: Words
        let sv: Words
    }

    struct Words: Decodable, Sendable {
        let title: String
        let cue: String
    }

    /// Decoded once, on first use (~100 KB).
    private static let entries: [String: Entry] = load()

    static func load(bundle: Bundle = .main) -> [String: Entry] {
        guard let url = bundle.url(forResource: "exercise-steps", withExtension: "json") else {
            AppLog.training.error("ExerciseStepGuide: exercise-steps.json missing from bundle")
            return [:]
        }
        do {
            return try JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: url))
        } catch {
            AppLog.training.error("ExerciseStepGuide: decode failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }
}
