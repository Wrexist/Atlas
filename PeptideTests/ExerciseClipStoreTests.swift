import XCTest
@testable import Peptide

/// The clip store only asks for clips the branch's index lists, and falls
/// back to nil (the body map) on anything else.
@MainActor
final class ExerciseClipStoreTests: XCTestCase {

    private let transparent = ExerciseClipStore.Source(
        baseURL: URL(string: "https://clips.test/alpha/")!, indexName: "clips.txt", fileExtension: "mov", isTransparent: true
    )
    private let opaque = ExerciseClipStore.Source(
        baseURL: URL(string: "https://clips.test/opaque/")!, indexName: "index.txt", fileExtension: "mp4", isTransparent: false
    )
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
        return ExerciseClipStore(sources: [transparent, opaque], session: URLSession(configuration: config), cacheDirectory: cacheDirectory)
    }

    func test_parseIndex_ignoresBlankLinesAndWhitespace() {
        let ids = ExerciseClipStore.parseIndex("Barbell_Squat\n\n  Side_Lateral_Raise \r\nPushups 1a2b3c4d\n")
        XCTAssertEqual(ids, ["Barbell_Squat": "", "Side_Lateral_Raise": "", "Pushups": "1a2b3c4d"])
    }

    func test_clip_listedExercise_downloadsOnceThenServesFromCache() async throws {
        let video = Data([0, 0, 0, 24])
        let requests = AttemptCounter()
        let store = store(serving: ["clips.txt": Data("Barbell_Squat\n".utf8), "Barbell_Squat.mov": video],
                          requests: requests)

        let downloaded = await store.clip(for: "Barbell_Squat")
        let first = try XCTUnwrap(downloaded)
        XCTAssertTrue(first.isTransparent)
        XCTAssertEqual(try Data(contentsOf: first.url), video)
        let fetchesAfterFirst = requests.value

        let second = await store.clip(for: "Barbell_Squat")
        XCTAssertEqual(second, first)
        XCTAssertEqual(requests.value, fetchesAfterFirst)
    }

    func test_clip_exerciseNotInIndex_returnsNilWithoutFetchingVideo() async {
        let requests = AttemptCounter()
        let store = store(serving: ["clips.txt": Data("Barbell_Squat\n".utf8)], requests: requests)

        let clip = await store.clip(for: "Pushups")

        XCTAssertNil(clip)
        XCTAssertEqual(requests.value, 2, "only the two indexes are fetched")
    }

    func test_remoteURL_versionedClip_carriesTheVersionSoTheCDNServesTheNewBytes() {
        let url = ExerciseClipStore.remoteURL("Pushups", version: "bbbb", in: transparent)
        XCTAssertEqual(url.absoluteString, "https://clips.test/alpha/Pushups.mov?v=bbbb")
    }

    func test_remoteURL_unversionedClip_isThePlainFile() {
        let url = ExerciseClipStore.remoteURL("Pushups", version: "", in: opaque)
        XCTAssertEqual(url.absoluteString, "https://clips.test/opaque/Pushups.mp4")
    }

    func test_clip_newVersionInIndex_replacesCachedClip() async throws {
        let old = Data([1]), new = Data([2])
        let first = store(serving: ["clips.txt": Data("Pushups aaaa\n".utf8), "Pushups.mov": old])
        _ = await first.clip(for: "Pushups")

        let second = store(serving: ["clips.txt": Data("Pushups bbbb\n".utf8), "Pushups.mov": new])
        let fetched = await second.clip(for: "Pushups")
        let clip = try XCTUnwrap(fetched)

        XCTAssertEqual(try Data(contentsOf: clip.url), new)
        let cached = try FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path)
        XCTAssertEqual(cached, ["Pushups@bbbb.mov"])
    }

    func test_clip_droppedFromIndex_returnsNilEvenWhenCached() async {
        let first = store(serving: ["clips.txt": Data("Pushups aaaa\n".utf8), "Pushups.mov": Data([1])])
        _ = await first.clip(for: "Pushups")

        let second = store(serving: ["clips.txt": Data("Barbell_Squat\n".utf8)])
        let clip = await second.clip(for: "Pushups")

        XCTAssertNil(clip)
    }

    func test_clip_indexUnavailable_servesCachedClip() async throws {
        let first = store(serving: ["clips.txt": Data("Pushups aaaa\n".utf8), "Pushups.mov": Data([1])])
        let downloaded = await first.clip(for: "Pushups")
        let cached = try XCTUnwrap(downloaded)

        let offline = store(serving: [:])
        let clip = await offline.clip(for: "Pushups")

        XCTAssertEqual(clip?.url.lastPathComponent, cached.url.lastPathComponent)
    }

    func test_clip_indexUnavailable_returnsNilAndRetriesNextTime() async {
        let requests = AttemptCounter()
        let store = store(serving: [:], requests: requests)

        let first = await store.clip(for: "Barbell_Squat")
        let second = await store.clip(for: "Barbell_Squat")

        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(requests.value, 4, "both indexes are tried on each attempt")
    }

    func test_clip_transparentSetMissing_fallsBackToOpaqueClips() async throws {
        let video = Data([7])
        let store = store(serving: ["index.txt": Data("Barbell_Squat\n".utf8), "Barbell_Squat.mp4": video])

        let fetched = await store.clip(for: "Barbell_Squat")
        let clip = try XCTUnwrap(fetched)

        XCTAssertFalse(clip.isTransparent)
        XCTAssertEqual(clip.url.pathExtension, "mp4")
        XCTAssertEqual(try Data(contentsOf: clip.url), video)
    }

    func test_clip_exerciseNotYetRerendered_keepsItsOpaqueClip() async throws {
        let store = store(serving: ["clips.txt": Data("Pushups\n".utf8), "Pushups.mov": Data([2]),
                                    "index.txt": Data("Pushups\nBarbell_Squat\n".utf8), "Barbell_Squat.mp4": Data([1])])

        let squat = await store.clip(for: "Barbell_Squat")
        let pushups = await store.clip(for: "Pushups")

        XCTAssertEqual(squat?.isTransparent, false)
        XCTAssertEqual(pushups?.isTransparent, true)
    }

    func test_clip_transparentIndexFailsOnce_keepsTheCachedTransparentClip() async throws {
        let both = store(serving: ["clips.txt": Data("Pushups\n".utf8), "Pushups.mov": Data([2])])
        _ = await both.clip(for: "Pushups")

        let opaqueOnly = store(serving: ["index.txt": Data("Pushups\n".utf8), "Pushups.mp4": Data([1])])
        _ = await opaqueOnly.clip(for: "Pushups")

        let cached = try FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path).sorted()
        XCTAssertEqual(cached, ["Pushups.mov", "Pushups.mp4"])
    }

    func test_clip_transparentSetPublished_replacesTheCachedOpaqueClip() async throws {
        let opaqueOnly = store(serving: ["index.txt": Data("Pushups\n".utf8), "Pushups.mp4": Data([1])])
        _ = await opaqueOnly.clip(for: "Pushups")

        let both = store(serving: ["clips.txt": Data("Pushups aaaa\n".utf8), "Pushups.mov": Data([2]),
                                   "index.txt": Data("Pushups\n".utf8), "Pushups.mp4": Data([1])])
        let fetched = await both.clip(for: "Pushups")
        let clip = try XCTUnwrap(fetched)

        XCTAssertTrue(clip.isTransparent)
        let cached = try FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path)
        XCTAssertEqual(cached, ["Pushups@aaaa.mov"])
    }
}
