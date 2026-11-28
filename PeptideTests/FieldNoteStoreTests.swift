import UIKit
import XCTest
@testable import Peptide

@MainActor
final class FieldNoteStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FieldNoteStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        try await super.tearDown()
    }

    private func screenshot() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    func test_add_blankText_savesNothing() {
        let store = FieldNoteStore(directory: directory)
        store.add(text: "  \n ", screen: "Train", screenshot: nil)
        XCTAssertTrue(store.notes.isEmpty)
    }

    func test_add_trimsTextAndSurvivesRelaunch() {
        let store = FieldNoteStore(directory: directory)
        store.add(text: "  Rest timer too loud \n", screen: "Train", screenshot: screenshot())

        let reloaded = FieldNoteStore(directory: directory)
        XCTAssertEqual(reloaded.notes.map(\.text), ["Rest timer too loud"])
        XCTAssertEqual(reloaded.notes.first?.screen, "Train")
        XCTAssertNotNil(reloaded.notes.first?.screenshotFilename)
    }

    func test_exportFiles_givesMarkdownFirstThenEachScreenshot() throws {
        let store = FieldNoteStore(directory: directory)
        store.add(text: "One", screen: "Today", screenshot: screenshot())
        store.add(text: "Two", screen: "Meals", screenshot: nil)

        let files = store.exportFiles()

        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files.first?.pathExtension, "md")
        XCTAssertEqual(files.last?.pathExtension, "jpg")
        let markdown = try String(contentsOf: try XCTUnwrap(files.first), encoding: .utf8)
        XCTAssertTrue(markdown.contains("One"))
        XCTAssertTrue(markdown.contains("Two"))
    }

    func test_exportFiles_noNotes_isEmpty() {
        XCTAssertTrue(FieldNoteStore(directory: directory).exportFiles().isEmpty)
    }

    func test_deleteAll_removesNotesAndFiles() {
        let store = FieldNoteStore(directory: directory)
        store.add(text: "Gone soon", screen: "Habits", screenshot: screenshot())

        store.deleteAll()

        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertTrue(FieldNoteStore(directory: directory).notes.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func test_render_newestFirstWithTimeScreenAndScreenshot() throws {
        let utc = TimeZone(identifier: "UTC")!
        let older = FieldNote(
            id: UUID(), createdAt: Date(timeIntervalSince1970: 1_796_126_400),
            screen: "Train", text: "Older", screenshotFilename: nil
        )
        let newer = FieldNote(
            id: UUID(), createdAt: Date(timeIntervalSince1970: 1_796_130_000),
            screen: "Meals · sheet", text: "Newer", screenshotFilename: "note-abc.jpg"
        )

        let markdown = FieldNoteMarkdown.render([older, newer], timeZone: utc)

        XCTAssertTrue(markdown.hasPrefix("# Atlas notes (2)"))
        XCTAssertTrue(markdown.contains("## 2026-12-01 13:00 · Meals · sheet\n\nNewer\n\nScreenshot: note-abc.jpg"))
        XCTAssertLessThan(
            try XCTUnwrap(markdown.range(of: "Newer")).lowerBound,
            try XCTUnwrap(markdown.range(of: "Older")).lowerBound
        )
    }
}
