import XCTest
import UIKit
@testable import Peptide

@MainActor
final class TrainingAnatomyTests: XCTestCase {
    func test_regionNamesDistinguishEveryPickerChoice() {
        XCTAssertEqual(Set(AnatomicalMuscle.allCases.map(\.regionName)).count,
                       AnatomicalMuscle.allCases.count)
    }

    func test_bodyHitTestingPreservesExactHitsAndRejectsDistantBackground() {
        let rect = CGRect(x: 0, y: 0, width: 1024, height: 1536)
        let front = AnatomicalMuscle.allCases.filter { !$0.isBack }
        XCTAssertEqual(TrainingAnatomy.hitTest(CGPoint(x: 440, y: 360), in: rect,
                                             candidates: front), .pecSternal)
        XCTAssertNil(TrainingAnatomy.hitTest(CGPoint(x: 100, y: 100), in: rect,
                                           candidates: front))
        // Just outside the chest's lateral boundary, without another candidate
        // stealing the nearby hit. Zero tolerance must preserve exact behavior.
        let nearby = CGPoint(x: 368, y: 365)
        XCTAssertNil(TrainingAnatomy.hitTest(nearby, in: rect, candidates: [.pecSternal], tolerance: 0))
        XCTAssertEqual(TrainingAnatomy.hitTest(nearby, in: rect, candidates: [.pecSternal]), .pecSternal)
    }

    func test_bodyMapAssetsCoverEveryRegionWithAlignedCanvas() throws {
        XCTAssertTrue(TrainingAnatomy.isAvailable)
        XCTAssertEqual(Set(TrainingAnatomy.regions.keys), Set(AnatomicalMuscle.allCases.map(\.rawValue)))
        let front = try XCTUnwrap(UIImage(named: TrainingAnatomy.front))
        let back = try XCTUnwrap(UIImage(named: TrainingAnatomy.back))
        XCTAssertEqual(front.size, back.size)
        let rect = CGRect(x: 0, y: 0, width: 1024, height: 1536)
        for muscle in AnatomicalMuscle.allCases {
            let path = TrainingAnatomy.path(for: muscle, in: rect)
            XCTAssertFalse(path.isEmpty, muscle.rawValue)
            XCTAssertTrue(rect.contains(path.boundingRect), muscle.rawValue)
            XCTAssertEqual(path.boundingRect.midX, CGFloat(TrainingAnatomy.mirrorAxis), accuracy: 0.01)
        }
    }

    func test_regionGeometry_isAuthoredOnOneSideInsideTheArtwork() {
        for muscle in AnatomicalMuscle.allCases {
            let points = TrainingAnatomy.regions[muscle.rawValue] ?? []
            XCTAssertGreaterThanOrEqual(points.count, 3, muscle.rawValue)
            for point in points {
                XCTAssertEqual(point.count, 2, muscle.rawValue)
                XCTAssertTrue((0..<TrainingAnatomy.mirrorAxis).contains(point[0]), muscle.rawValue)
                XCTAssertTrue((0...1536).contains(point[1]), muscle.rawValue)
            }
        }
    }
}
