import Foundation

/// Rendered exercise animations: 3-second loops of the Atlas figure doing
/// the movement, trained muscles tinted. They are too big to bundle, so they
/// stream from the repo and each clip is saved to Caches after its first
/// download.
///
/// Two sources, in priority order. The `exercise-videos-alpha` branch holds
/// the transparent re-render (HEVC with alpha, so the figure sits straight on
/// the card); the `exercise-videos` branch holds the older opaque clips
/// (black background). Each exercise uses the first source that lists it, so
/// while the re-render is published batch by batch, an exercise not yet in
/// it keeps its opaque clip, and the app switches to the new clips by itself.
/// The opaque index carries no versions, so an opaque clip is never refreshed
/// once cached; that set is frozen.
///
/// A source's index lists the exercise ids that have a clip, each optionally
/// followed by a version (a hash of the clip). A re-rendered clip gets a new
/// version, so the cached copy is replaced; an id dropped from the index
/// stops showing even if it is cached. Any other id (a custom exercise, one
/// not rendered yet) gives nil, and the detail screen keeps showing the body
/// map alone. Offline, a cached clip is still shown.
@MainActor
final class ExerciseClipStore {
    static let shared = ExerciseClipStore()

    struct Source: Sendable {
        let baseURL: URL
        let indexName: String
        let fileExtension: String
        let isTransparent: Bool
    }

    private struct LoadedIndex: Sendable {
        let source: Source
        let ids: [String: String]
    }

    struct Clip: Equatable, Sendable {
        let url: URL
        /// False for the opaque clips, which the card frames as a panel.
        let isTransparent: Bool
    }

    nonisolated static let alpha = Source(
        baseURL: URL.staticHTTPS("https://raw.githubusercontent.com/Wrexist/Atlas/exercise-videos-alpha/"),
        indexName: "clips.txt", fileExtension: "mov", isTransparent: true
    )
    nonisolated static let opaque = Source(
        baseURL: URL.staticHTTPS("https://raw.githubusercontent.com/Wrexist/Atlas/exercise-videos/"),
        indexName: "index.txt", fileExtension: "mp4", isTransparent: false
    )

    private let sources: [Source]
    private let session: URLSession
    private let cacheDirectory: URL
    private var available: [LoadedIndex]?
    private var indexTask: Task<[LoadedIndex]?, Never>?

    init(
        sources: [Source] = [ExerciseClipStore.alpha, ExerciseClipStore.opaque],
        session: URLSession = .shared,
        cacheDirectory: URL = URL.cachesDirectory.appending(path: "exercise-clips-alpha", directoryHint: .isDirectory)
    ) {
        self.sources = sources
        self.session = session
        self.cacheDirectory = cacheDirectory
    }

    /// A local file URL for the exercise's clip, downloading it first if
    /// needed; nil when there is no clip or the network is unavailable and
    /// nothing is cached.
    func clip(for exerciseID: String) async -> Clip? {
        guard let indexes = await indexes() else { return cachedClip(for: exerciseID) }
        guard let index = indexes.first(where: { $0.ids[exerciseID] != nil }),
              let version = index.ids[exerciseID] else { return nil }
        let source = index.source
        let file = cacheDirectory.appending(path: Self.fileName(exerciseID, version: version, fileExtension: source.fileExtension))
        let clip = Clip(url: file, isTransparent: source.isTransparent)
        if FileManager.default.fileExists(atPath: file.path) { return clip }
        let remote = Self.remoteURL(exerciseID, version: version, in: source)
        guard await download(remote, to: file) else { return nil }
        removeCachedClips(for: exerciseID, except: file, from: source)
        return clip
    }

    /// Whether the exercise has a clip, from the indexes alone, so a screen
    /// can hold the clip's place while the video itself downloads. Offline,
    /// a cached clip counts.
    func hasClip(for exerciseID: String) async -> Bool {
        guard let indexes = await indexes() else { return cachedClip(for: exerciseID) != nil }
        return indexes.contains { $0.ids[exerciseID] != nil }
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

    /// The clip's download URL. The version rides along as a query so a
    /// re-rendered clip is a new URL: raw.githubusercontent.com's CDN caches
    /// each URL for minutes, and the old bytes would otherwise be saved under
    /// the new version's name for good.
    nonisolated static func remoteURL(_ exerciseID: String, version: String, in source: Source) -> URL {
        let file = source.baseURL.appending(path: "\(exerciseID).\(source.fileExtension)")
        return version.isEmpty ? file : file.appending(queryItems: [URLQueryItem(name: "v", value: version)])
    }

    nonisolated static func fileName(_ exerciseID: String, version: String, fileExtension: String) -> String {
        version.isEmpty ? "\(exerciseID).\(fileExtension)" : "\(exerciseID)@\(version).\(fileExtension)"
    }

    private func cachedFiles(for exerciseID: String) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        return files.filter {
            let stem = $0.deletingPathExtension().lastPathComponent
            return stem == exerciseID || stem.hasPrefix("\(exerciseID)@")
        }
    }

    /// Offline fallback: a transparent clip wins over an opaque one.
    private func cachedClip(for exerciseID: String) -> Clip? {
        let clips = cachedFiles(for: exerciseID).map { file in
            Clip(url: file, isTransparent: sources.contains { $0.isTransparent && $0.fileExtension == file.pathExtension })
        }
        return clips.first(where: \.isTransparent) ?? clips.first
    }

    /// Drops older copies from the same source and any opaque copy once a
    /// transparent one is in. A transparent copy is never dropped for an
    /// opaque one, since that only happens when the transparent index failed
    /// to load this launch.
    private func removeCachedClips(for exerciseID: String, except keep: URL, from source: Source) {
        let rank = sources.firstIndex { $0.fileExtension == source.fileExtension } ?? 0
        let replaceable = Set(sources[rank...].map(\.fileExtension))
        for file in cachedFiles(for: exerciseID)
        where file.lastPathComponent != keep.lastPathComponent && replaceable.contains(file.pathExtension) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// The indexes that loaded, in priority order; fetched once per launch.
    /// When none loads, nothing is remembered, so the next screen tries again.
    private func indexes() async -> [LoadedIndex]? {
        if let available { return available }
        if let indexTask { return await indexTask.value }
        let task = Task { await fetchIndex() }
        indexTask = task
        let loaded = await task.value
        available = loaded
        indexTask = nil
        return loaded
    }

    private func fetchIndex() async -> [LoadedIndex]? {
        var loaded: [LoadedIndex] = []
        for source in sources {
            if let data = await fetch(source.baseURL.appending(path: source.indexName)) {
                loaded.append(LoadedIndex(source: source, ids: Self.parseIndex(String(decoding: data, as: UTF8.self))))
            }
        }
        return loaded.isEmpty ? nil : loaded
    }

    private func download(_ url: URL, to file: URL) async -> Bool {
        guard let data = await fetch(url) else { return false }
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func fetch(_ url: URL) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
