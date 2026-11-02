import Foundation

/// Rendered exercise animations: 3-second loops of the Atlas figure doing
/// the movement, trained muscles tinted. They are too big to bundle, so they
/// stream from the repo's `exercise-videos` branch and each clip is saved to
/// Caches after its first download.
///
/// The branch's `index.txt` lists the exercise ids that have a clip. Any
/// other id (a custom exercise, one not rendered yet) or a failed fetch
/// gives nil, and the detail screen keeps showing the body map alone.
@MainActor
final class ExerciseClipStore {
    static let shared = ExerciseClipStore()

    nonisolated static let defaultBaseURL = URL.staticHTTPS("https://raw.githubusercontent.com/Wrexist/Atlas/exercise-videos/")

    private let baseURL: URL
    private let session: URLSession
    private let cacheDirectory: URL
    private var available: Set<String>?
    private var indexTask: Task<Set<String>?, Never>?

    init(
        baseURL: URL = ExerciseClipStore.defaultBaseURL,
        session: URLSession = .shared,
        cacheDirectory: URL = URL.cachesDirectory.appending(path: "exercise-clips", directoryHint: .isDirectory)
    ) {
        self.baseURL = baseURL
        self.session = session
        self.cacheDirectory = cacheDirectory
    }

    /// A local file URL for the exercise's clip, downloading it first if
    /// needed; nil when there is no clip or the network is unavailable.
    func clip(for exerciseID: String) async -> URL? {
        let file = cacheDirectory.appending(path: "\(exerciseID).mp4")
        if FileManager.default.fileExists(atPath: file.path) { return file }
        guard let ids = await index(), ids.contains(exerciseID) else { return nil }
        return await download(baseURL.appending(path: "\(exerciseID).mp4"), to: file)
    }

    /// One line per exercise id; blank lines and whitespace are ignored.
    nonisolated static func parseIndex(_ text: String) -> Set<String> {
        Set(text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
    }

    /// Fetched once per launch. A failed fetch isn't remembered, so the next
    /// screen tries again.
    private func index() async -> Set<String>? {
        if let available { return available }
        if let indexTask { return await indexTask.value }
        let task = Task { await fetchIndex() }
        indexTask = task
        let ids = await task.value
        available = ids
        indexTask = nil
        return ids
    }

    private func fetchIndex() async -> Set<String>? {
        guard let data = await fetch(baseURL.appending(path: "index.txt")) else { return nil }
        return Self.parseIndex(String(decoding: data, as: UTF8.self))
    }

    private func download(_ url: URL, to file: URL) async -> URL? {
        guard let data = await fetch(url) else { return nil }
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            return file
        } catch {
            return nil
        }
    }

    private func fetch(_ url: URL) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
