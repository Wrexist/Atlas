import XCTest
@testable import Peptide

/// The clip store only asks for clips the branch's index lists, and falls
/// back to nil (the body map) on anything else.
@MainActor
final class ExerciseClipStoreTests: XCTestCase {

    private let base = URL(string: "https://clips.test/")!
    private var cacheDirectory: URL!

    override func setUp() {
        super.setUp()
        cacheDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        addTeardownBlock { [cacheDirectory] in
            MockURLProtocol.reset()
            try? FileManager.default.removeItem(at: cacheDirectory!)
        }
    }

    private func store(serving files: [String: Data], requests: AttemptCounter = AttemptCounter()) -> ExerciseClipStore {
        MockURLProtocol.handler = { request in
            requests.bump()
            let name = request.url!.lastPathComponent
            let status = files[name] == nil ? 404 : 200
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, files[name] ?? Data())
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return ExerciseClipStore(baseURL: base, session: URLSession(configuration: config), cacheDirectory: cacheDirectory)
    }

    func test_parseIndex_ignoresBlankLinesAndWhitespace() {
        let ids = ExerciseClipStore.parseIndex("Barbell_Squat\n\n  Side_Lateral_Raise \r\nPushups\n")
        XCTAssertEqual(ids, ["Barbell_Squat", "Side_Lateral_Raise", "Pushups"])
    }

    func test_clip_listedExercise_downloadsOnceThenServesFromCache() async throws {
        let video = Data([0, 0, 0, 24])
        let requests = AttemptCounter()
        let store = store(serving: ["index.txt": Data("Barbell_Squat\n".utf8), "Barbell_Squat.mp4": video],
                          requests: requests)

        let first = try XCTUnwrap(await store.clip(for: "Barbell_Squat"))
        XCTAssertEqual(try Data(contentsOf: first), video)
        let fetchesAfterFirst = requests.value

        let second = await store.clip(for: "Barbell_Squat")
        XCTAssertEqual(second, first)
        XCTAssertEqual(requests.value, fetchesAfterFirst)
    }

    func test_clip_exerciseNotInIndex_returnsNilWithoutFetchingVideo() async {
        let requests = AttemptCounter()
        let store = store(serving: ["index.txt": Data("Barbell_Squat\n".utf8)], requests: requests)

        let clip = await store.clip(for: "Pushups")

        XCTAssertNil(clip)
        XCTAssertEqual(requests.value, 1)
    }

    func test_clip_indexUnavailable_returnsNilAndRetriesNextTime() async {
        let requests = AttemptCounter()
        let store = store(serving: [:], requests: requests)

        let first = await store.clip(for: "Barbell_Squat")
        let second = await store.clip(for: "Barbell_Squat")

        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(requests.value, 2)
    }
}
