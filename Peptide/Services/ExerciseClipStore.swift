import Foundation

/// Rendered exercise animations: 3-second loops of the Atlas figure doing
/// the movement, trained muscles tinted, on a transparent background (HEVC
/// with alpha) so the figure sits straight on the card in light and dark
/// mode. They are too big to bundle, so they stream from the repo's
/// `exercise-videos-alpha` branch and each clip is saved to Caches after its
/// first download.
///
/// The branch's `clips.txt` lists the exercise ids that have a clip, each
/// optionally followed by a version (a hash of the clip). A re-rendered clip
/// gets a new version, so the cached copy is replaced; an id dropped from the
/// index stops showing even if it is cached. Any other id (a custom exercise,
/// one not rendered yet) gives nil, and the detail screen keeps showing the
/// body map alone. Offline, a cached clip is still shown.
@MainActor
final class ExerciseClipStore {
    static let shared = ExerciseClipStore()

    nonisolated static let defaultBaseURL = URL.staticHTTPS("https://raw.githubusercontent.com/Wrexist/Atlas/exercise-videos-alpha/")

    private let baseURL: URL
    private let session: URLSession
    private let cacheDirectory: URL
    private var available: [String: String]?
    private var indexTask: Task<[String: String]?, Never>?

    init(
        baseURL: URL = ExerciseClipStore.defaultBaseURL,
        session: URLSession = .shared,
        cacheDirectory: URL = URL.cachesDirectory.appending(path: "exercise-clips-alpha", directoryHint: .isDirectory)
    ) {
        self.baseURL = baseURL
        self.session = session
        self.cacheDirectory = cacheDirectory
    }

    /// A local file URL for the exercise's clip, downloading it first if
    /// needed; nil when there is no clip or the network is unavailable and
    /// nothing is cached.
    func clip(for exerciseID: String) async -> URL? {
        guard let ids = await index() else { return cachedClip(for: exerciseID) }
        guard let version = ids[exerciseID] else { return nil }
        let file = cacheDirectory.appending(path: Self.fileName(exerciseID, version: version))
        if FileManager.default.fileExists(atPath: file.path) { return file }
        guard let downloaded = await download(baseURL.appending(path: "\(exerciseID).mov"), to: file) else { return nil }
        removeCachedClips(for: exerciseID, except: file)
        return downloaded
    }

    /// One line per exercise id, optionally followed by whitespace and a
    /// version; blank lines and surrounding whitespace are ignored.
    nonisolated static func parseIndex(_ text: String) -> [String: String] {
        var ids: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard let id = fields.first else { continue }
            ids[String(id)] = fields.count > 1 ? String(fields[1]) : ""
        }
        return ids
    }

    nonisolated static func fileName(_ exerciseID: String, version: String) -> String {
        version.isEmpty ? "\(exerciseID).mov" : "\(exerciseID)@\(version).mov"
    }

    private func cachedFiles(for exerciseID: String) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        return files.filter {
            let name = $0.lastPathComponent
            return name == "\(exerciseID).mov" || (name.hasPrefix("\(exerciseID)@") && name.hasSuffix(".mov"))
        }
    }

    private func cachedClip(for exerciseID: String) -> URL? {
        cachedFiles(for: exerciseID).first
    }

    private func removeCachedClips(for exerciseID: String, except keep: URL) {
        for file in cachedFiles(for: exerciseID) where file.lastPathComponent != keep.lastPathComponent {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Fetched once per launch. A failed fetch isn't remembered, so the next
    /// screen tries again.
    private func index() async -> [String: String]? {
        if let available { return available }
        if let indexTask { return await indexTask.value }
        let task = Task { await fetchIndex() }
        indexTask = task
        let ids = await task.value
        available = ids
        indexTask = nil
        return ids
    }

    private func fetchIndex() async -> [String: String]? {
        guard let data = await fetch(baseURL.appending(path: "clips.txt")) else { return nil }
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
