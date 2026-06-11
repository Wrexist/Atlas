import SwiftUI
import XCTest
@testable import Peptide

/// Pins the pure logic inside the Live Activity controller (audit
/// Phase 9): the active-window boundaries that decide when a dose
/// surfaces on the Lock Screen, and the Color → packed-RGB hex
/// round-trip the widget rebuilds its tint from. The ActivityKit
/// side effects (request/update/end) stay untested here — they
/// require system authorisation a unit host never has.
@MainActor
final class DoseLiveActivityServiceTests: XCTestCase {

    private let calendar = Calendar.current
    private let doseTime = Date()

    private func minutes(_ offset: Int) -> Date {
        calendar.date(byAdding: .minute, value: offset, to: doseTime)!
    }

    private func makeEntry(completed: Bool = false) -> ProtocolEntry {
        ProtocolEntry(
            id: UUID(),
            protocolId: UUID(),
            peptide: MockPeptides.bpc157,
            date: doseTime,
            dose: "250mcg",
            notes: "",
            completed: completed
        )
    }

    // MARK: - Active window (30 min lead → 90 min staleness)

    func test_isInActiveWindow_trueAtScheduledTime() {
        XCTAssertTrue(DoseLiveActivityService.isInActiveWindow(makeEntry(), at: doseTime))
    }

    func test_isInActiveWindow_inclusiveAtLeadBoundary() {
        XCTAssertTrue(DoseLiveActivityService.isInActiveWindow(makeEntry(), at: minutes(-30)))
        XCTAssertFalse(DoseLiveActivityService.isInActiveWindow(makeEntry(), at: minutes(-31)))
    }

    func test_isInActiveWindow_inclusiveAtStalenessBoundary() {
        XCTAssertTrue(DoseLiveActivityService.isInActiveWindow(makeEntry(), at: minutes(90)))
        XCTAssertFalse(DoseLiveActivityService.isInActiveWindow(makeEntry(), at: minutes(91)))
    }

    func test_isInActiveWindow_false_forCompletedEntries() {
        // A logged dose must never resurrect a Lock Screen banner,
        // even squarely inside the window.
        XCTAssertFalse(DoseLiveActivityService.isInActiveWindow(makeEntry(completed: true), at: doseTime))
    }

    // MARK: - Color → packed RGB hex

    func test_hex_packsPrimariesAndExtremes() {
        XCTAssertEqual(DoseLiveActivityService.hex(of: Color(red: 1, green: 0, blue: 0)), 0xFF0000)
        XCTAssertEqual(DoseLiveActivityService.hex(of: Color(red: 0, green: 1, blue: 0)), 0x00FF00)
        XCTAssertEqual(DoseLiveActivityService.hex(of: Color(red: 0, green: 0, blue: 1)), 0x0000FF)
        XCTAssertEqual(DoseLiveActivityService.hex(of: Color(red: 1, green: 1, blue: 1)), 0xFFFFFF)
        XCTAssertEqual(DoseLiveActivityService.hex(of: Color(red: 0, green: 0, blue: 0)), 0x000000)
    }

    func test_hex_clampsOutOfRangeComponents() {
        // Extended-sRGB inputs outside 0...1 must clamp, not wrap —
        // a wrapped byte would tint the widget a wildly wrong color.
        XCTAssertEqual(DoseLiveActivityService.hex(of: Color(red: 1.5, green: -0.2, blue: 0)), 0xFF0000)
    }
}
