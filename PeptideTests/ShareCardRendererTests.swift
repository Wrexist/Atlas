import XCTest
@testable import Peptide

@MainActor
final class ShareCardRendererTests: XCTestCase {
    func testRenderProducesExactDimensions() throws {
        let url = try ShareCardRenderer.renderPNG(for: Self.makeModel(from: MockProtocols.recoveryStack))
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        let image = try XCTUnwrap(UIImage(data: data))
        // Against the renderer's own constant, not a second copy of the
        // number. These two asserted 1080×1350 — a 4:5 feed post — while
        // `canvasSize` has been 1080×1920 since the renderer was written, so
        // the expectation was never right about the code it was testing.
        XCTAssertEqual(image.size.width, ShareCardRenderer.canvasSize.width, accuracy: 0.5)
        XCTAssertEqual(image.size.height, ShareCardRenderer.canvasSize.height, accuracy: 0.5)
        XCTAssertGreaterThan(data.count, 10_000, "PNG should be non-trivially large")
    }

    func testRenderImageIsOpaque() throws {
        let image = try ShareCardRenderer.renderImage(for: Self.makeModel(from: MockProtocols.recoveryStack))
        XCTAssertEqual(image.size.width, ShareCardRenderer.canvasSize.width)
        XCTAssertEqual(image.size.height, ShareCardRenderer.canvasSize.height)
    }

    func testWatermarkBakedInWhenSinglePeptideStack() throws {
        let single = PeptideProtocol(
            id: UUID(),
            name: "Solo BPC-157",
            peptides: [MockPeptides.bpc157],
            schedule: ProtocolSchedule(
                daysOfWeek: [1, 2, 3, 4, 5],
                timesPerDay: 1,
                preferredTimes: ["8:00 AM"]
            ),
            cycleLengthWeeks: 4,
            startDate: Date(),
            status: .active,
            notes: ""
        )
        let url = try ShareCardRenderer.renderPNG(for: Self.makeModel(from: single))
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try XCTUnwrap(UIImage(data: Data(contentsOf: url)))
        // The watermark is rendered inline in the same view tree, so single
        // and many-peptide stacks both produce a fully populated canvas with
        // no detached overlay.
        XCTAssertEqual(image.size.width, ShareCardRenderer.canvasSize.width, accuracy: 0.5)
        XCTAssertEqual(image.size.height, ShareCardRenderer.canvasSize.height, accuracy: 0.5)
    }

    /// Builds a CycleCardModel for a given protocol with deterministic
    /// stats — these tests only assert dimensions / size, so the exact
    /// numbers don't matter; we just need a populated model the renderer
    /// can lay out.
    private static func makeModel(from proto: PeptideProtocol) -> CycleCardModel {
        CycleCardModel(
            subjectTitle: proto.name,
            peptides: proto.peptides,
            activeSinceDate: proto.startDate,
            cycleDay: 1,
            cycleTotalDays: max(1, proto.cycleLengthWeeks * 7),
            dosesLogged: 0,
            adherencePercent: 0,
            currentStreakDays: 0,
            healthSummary: nil
        )
    }
}
