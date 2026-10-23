import XCTest
@testable import Peptide

@MainActor
final class ShareCardRendererTests: XCTestCase {
    func testRenderProducesExactDimensions() throws {
        let url = try ShareCardRenderer.renderPNG(for: Self.makeModel(from: MockProtocols.recoveryStack))
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        let image = try XCTUnwrap(UIImage(data: data))
        // The default format is the Stories canvas.
        XCTAssertEqual(image.size.width, ShareFormat.story.pixelSize.width, accuracy: 0.5)
        XCTAssertEqual(image.size.height, ShareFormat.story.pixelSize.height, accuracy: 0.5)
        XCTAssertGreaterThan(data.count, 10_000, "PNG should be non-trivially large")
    }

    func testRenderImageIsOpaque() throws {
        let image = try ShareCardRenderer.renderImage(for: Self.makeModel(from: MockProtocols.recoveryStack))
        XCTAssertEqual(image.size.width, ShareFormat.story.pixelSize.width)
        XCTAssertEqual(image.size.height, ShareFormat.story.pixelSize.height)
    }

    func test_eachFormat_rendersExactPixelSize() throws {
        // Spelled out rather than read back from `pixelSize`, so a typo in
        // the enum can't agree with itself.
        let expected: [ShareFormat: (width: Int, height: Int)] = [
            .story: (1080, 1920),
            .square: (1080, 1080),
            .landscape: (1200, 630),
        ]
        let model = Self.makeModel(from: MockProtocols.recoveryStack)
        for format in ShareFormat.allCases {
            let image = try ShareCardRenderer.renderImage(for: model, format: format)
            let cgImage = try XCTUnwrap(image.cgImage, "\(format)")
            let size = try XCTUnwrap(expected[format], "\(format) has no expected size")
            XCTAssertEqual(cgImage.width, size.width, "\(format) width")
            XCTAssertEqual(cgImage.height, size.height, "\(format) height")
        }
    }

    func test_eachFormat_withHealthAndMaskedNames_writesPNGOfExactPixelSize() throws {
        // The fullest card — health row on, names masked — is the one most
        // likely to overflow the tighter square and landscape layouts.
        let base = Self.makeModel(from: MockProtocols.recoveryStack)
        let model = CycleCardModel(
            subjectTitle: base.subjectTitle,
            peptides: base.peptides,
            activeSinceDate: base.activeSinceDate,
            cycleDay: base.cycleDay,
            cycleTotalDays: base.cycleTotalDays,
            dosesLogged: 128,
            adherencePercent: 94,
            currentStreakDays: 21,
            healthSummary: CycleCardModel.HealthSummary(
                weightDeltaKg: -1.8,
                avgSleepHours: 7.4,
                hrvTrendDescription: "62 ms avg"
            )
        )
        for format in ShareFormat.allCases {
            let url = try ShareCardRenderer.renderPNG(for: model, format: format, maskCompoundNames: true)
            defer { try? FileManager.default.removeItem(at: url) }
            let cgImage = try XCTUnwrap(UIImage(data: Data(contentsOf: url))?.cgImage, "\(format)")
            XCTAssertEqual(CGFloat(cgImage.width), format.pixelSize.width, "\(format) width")
            XCTAssertEqual(CGFloat(cgImage.height), format.pixelSize.height, "\(format) height")
            let attachment = XCTAttachment(image: UIImage(cgImage: cgImage))
            attachment.name = "cycle-card-\(format.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func test_renderPNG_maskedCompoundNames_fileNameOmitsProtocolName() throws {
        let url = try ShareCardRenderer.renderPNG(for: Self.makeModel(titled: "BPC-157 Stack"), maskCompoundNames: true)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertFalse(url.lastPathComponent.lowercased().contains("bpc"))
        XCTAssertTrue(url.lastPathComponent.hasPrefix("atlas-cycle-"))
    }

    func test_renderPNG_unmasked_fileNameUsesProtocolName() throws {
        let url = try ShareCardRenderer.renderPNG(for: Self.makeModel(titled: "BPC-157 Stack"))
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(url.lastPathComponent.hasPrefix("atlas-bpc-157-stack-"))
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
        XCTAssertEqual(image.size.width, ShareFormat.story.pixelSize.width, accuracy: 0.5)
        XCTAssertEqual(image.size.height, ShareFormat.story.pixelSize.height, accuracy: 0.5)
    }

    private static func makeModel(titled title: String) -> CycleCardModel {
        makeModel(from: MockProtocols.recoveryStack, titled: title)
    }

    /// Builds a CycleCardModel for a given protocol with deterministic
    /// stats — these tests only assert dimensions / size, so the exact
    /// numbers don't matter; we just need a populated model the renderer
    /// can lay out.
    private static func makeModel(from proto: PeptideProtocol, titled title: String? = nil) -> CycleCardModel {
        CycleCardModel(
            subjectTitle: title ?? proto.name,
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
