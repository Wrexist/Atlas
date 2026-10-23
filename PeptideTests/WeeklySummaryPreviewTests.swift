import XCTest
@testable import Peptide

final class WeeklySummaryPreviewTests: XCTestCase {

    func test_preview_shortText_isUnchanged() {
        let text = "Strong week. Keep going."
        XCTAssertEqual(WeeklySummary.preview(of: text, limit: 280), text)
    }

    func test_preview_decimalNearTheLimit_cutsAtTheSentenceNotTheDecimal() {
        let first = "Strong week with every dose logged."
        let second = " Your check-ins averaged 4.1 of 5 and sleep held at 7.5 h most nights."
        // The limit lands just after "4." inside the second sentence.
        let limit = first.count + " Your check-ins averaged 4.".count
        let preview = WeeklySummary.preview(of: first + second, limit: limit)

        XCTAssertEqual(preview, first + " …")
    }

    func test_preview_cutAtSentenceEnd_keepsThePeriod() {
        let text = "One. Two. " + String(repeating: "word ", count: 80)
        let preview = WeeklySummary.preview(of: text, limit: 20)
        XCTAssertEqual(preview, "One. Two. …")
    }

    func test_preview_firstSentenceTooLong_cutsAtAWord() {
        let text = String(repeating: "word ", count: 80) + "end."
        let preview = WeeklySummary.preview(of: text, limit: 12)
        XCTAssertEqual(preview, "word word…")
    }
}
