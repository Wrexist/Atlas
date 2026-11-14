import CoreGraphics
import XCTest
@testable import Peptide

/// The bundled step guides: only reviewed exercises, each with one to three
/// moments inside its 3-second clip, a crop inside the frame and short
/// cues in both languages.
@MainActor
final class ExerciseStepGuideTests: XCTestCase {

    private var entries: [String: ExerciseStepGuide.Entry] { ExerciseStepGuide.load() }

    override func setUp() async throws {
        try await super.setUp()
        await ExerciseLibrary.shared.load()
    }

    func test_bundledGuides_decodeAndCoverReviewedExercises() {
        XCTAssertGreaterThan(entries.count, 0, "exercise-steps.json is missing from the bundle or failed to decode")
    }

    func test_bundledGuides_everyIdIsABundledExercise() {
        for id in entries.keys {
            XCTAssertNotNil(ExerciseLibrary.shared.lookup(id: id), "\(id) has a guide but no exercise")
        }
    }

    func test_bundledGuides_oneToThreeStepsInOrderInsideTheClip() {
        for (id, entry) in entries {
            XCTAssertTrue((1...3).contains(entry.steps.count), "\(id): \(entry.steps.count) steps")
            let times = entry.steps.map(\.time)
            XCTAssertEqual(times, times.sorted(), "\(id): steps out of order")
            XCTAssertTrue(times.allSatisfy { (0..<3).contains($0) }, "\(id): a step falls outside the 3 s clip")
        }
    }

    func test_bundledGuides_cropIsInsideTheFrameAt4To5() {
        for (id, entry) in entries {
            let crop = CGRect(x: entry.crop[0], y: entry.crop[1], width: entry.crop[2], height: entry.crop[3])
            XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: -0.001, dy: -0.001).contains(crop), "\(id): crop leaves the frame")
            // Unit rect on a 720x900 clip: 4:5 in pixels is equal unit sides.
            XCTAssertEqual(crop.width, crop.height, accuracy: 0.01, "\(id): crop is not 4:5")
        }
    }

    func test_bundledGuides_cuesAreShortAndPresentInBothLanguages() {
        for (id, entry) in entries {
            for step in entry.steps {
                for words in [step.en, step.sv] {
                    XCTAssertFalse(words.title.isEmpty, "\(id): empty title")
                    XCTAssertFalse(words.cue.isEmpty, "\(id): empty cue")
                    XCTAssertLessThanOrEqual(words.title.count, 24, "\(id): title too long: \(words.title)")
                    XCTAssertLessThanOrEqual(words.cue.count, 70, "\(id): cue too long: \(words.cue)")
                }
            }
        }
    }

    func test_guide_swedishLocale_usesTheSwedishCues() throws {
        let id = try XCTUnwrap(entries.keys.sorted().first)
        let swedish = try XCTUnwrap(ExerciseStepGuide.guide(for: id, locale: Locale(identifier: "sv_SE")))
        let english = try XCTUnwrap(ExerciseStepGuide.guide(for: id, locale: Locale(identifier: "en_US")))

        XCTAssertEqual(swedish.steps.map(\.cue), entries[id]?.steps.map(\.sv.cue))
        XCTAssertEqual(english.steps.map(\.cue), entries[id]?.steps.map(\.en.cue))
    }

    func test_guide_otherLanguage_fallsBackToEnglish() throws {
        let id = try XCTUnwrap(entries.keys.sorted().first)
        let german = try XCTUnwrap(ExerciseStepGuide.guide(for: id, locale: Locale(identifier: "de_DE")))
        XCTAssertEqual(german.steps.map(\.title), entries[id]?.steps.map(\.en.title))
    }

    func test_guide_unreviewedExercise_isNilSoOnlyTheMuscleMapShows() {
        XCTAssertNil(ExerciseStepGuide.guide(for: "Not_A_Reviewed_Exercise", locale: Locale(identifier: "sv_SE")))
        XCTAssertFalse(ExerciseStepGuide.hasGuide(for: "Not_A_Reviewed_Exercise"))
    }

    func test_crop_unitRect_mapsToPixelsFromTheTopLeft() throws {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 720, height: 900, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())

        let cropped = try XCTUnwrap(ExerciseStepImageStore.crop(image, to: CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.5)))

        XCTAssertEqual(cropped.width, 360)
        XCTAssertEqual(cropped.height, 450)
    }
}
