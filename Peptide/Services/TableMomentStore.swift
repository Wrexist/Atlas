import Observation
import UIKit

/// Keeps the tables the user photographed: the moments as one JSON file
/// and each dish's cut-out as a PNG beside it, in Documents.
///
/// On-device only, like progress photos. The diary entries the dishes
/// logged sync as usual; on another device a table's dishes still count,
/// they just draw as plain plates.
@MainActor @Observable
final class TableMomentStore {
    static let shared = TableMomentStore()

    /// Where a keep is up to, for the "Adding 2 of 4 dishes…" pill.
    struct Progress: Equatable {
        enum Outcome: Equatable { case done, failed }
        let total: Int
        var saved = 0
        var outcome: Outcome?
    }

    /// What the review screen hands over when the user taps Keep.
    struct Draft {
        struct Dish {
            let entry: MealEntry
            let kind: DishKind
            let sticker: UIImage
        }
        /// Set when adding to a table already on file.
        var momentID: UUID?
        let date: Date
        let category: MealCategory
        let dishes: [Dish]
    }

    private(set) var moments: [TableMoment] = []
    private(set) var progress: Progress?

    /// The table whose diary write failed. Its dishes and reads cost an
    /// AI scan and can't be re-made, so the toast offers to retry it.
    @ObservationIgnored private var failedDraft: Draft?

    /// Cut-outs are drawn at most ~200 pt across; stored any larger they
    /// are only decode cost.
    static let stickerMaxEdge: CGFloat = 640

    @ObservationIgnored private let directory: URL?
    @ObservationIgnored private let stickers = NSCache<NSString, UIImage>()

    init(directory: URL? = TableMomentStore.defaultDirectory) {
        self.directory = directory
        moments = load()
    }

    nonisolated static var defaultDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TableMoments", isDirectory: true)
    }

    // MARK: - Reading

    func moment(id: UUID) -> TableMoment? {
        moments.first { $0.id == id }
    }

    func moments(on day: Date, calendar: Calendar = .current) -> [TableMoment] {
        moments.filter { calendar.isDate($0.date, inSameDayAs: day) }.sorted { $0.date < $1.date }
    }

    func sticker(for dish: TableDish) -> UIImage? {
        guard let filename = dish.stickerFilename else { return nil }
        if let cached = stickers.object(forKey: filename as NSString) { return cached }
        guard let url = directory?.appendingPathComponent(filename),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        stickers.setObject(image, forKey: filename as NSString)
        return image
    }

    // MARK: - Writing

    /// Logs the dishes, then writes their cut-outs one by one so the pill
    /// can count them in. The diary write comes first: if it fails nothing
    /// was eaten on paper, and no orphan stickers are left behind.
    func keep(_ draft: Draft, in dataStore: DataStore) async {
        guard !draft.dishes.isEmpty else { return }
        progress = Progress(total: draft.dishes.count)
        failedDraft = nil
        do {
            try dataStore.commitScannedMeals(draft.dishes.map(\.entry))
        } catch {
            AppLog.persistence.error("Table keep failed: \(error.localizedDescription, privacy: .public)")
            failedDraft = draft
            progress?.outcome = .failed
            Haptics.error()
            return
        }
        var dishes: [TableDish] = []
        for dish in draft.dishes {
            let filename = await writeSticker(dish.sticker)
            dishes.append(TableDish(
                id: dish.entry.id, name: dish.entry.name, kind: dish.kind, stickerFilename: filename,
                calories: dish.entry.calories, proteinG: dish.entry.proteinG
            ))
            progress?.saved += 1
        }
        if let id = draft.momentID, let index = moments.firstIndex(where: { $0.id == id }) {
            moments[index].dishes += dishes
        } else {
            moments.append(TableMoment(date: draft.date, category: draft.category, dishes: dishes))
        }
        persist()
        progress?.outcome = .done
        Haptics.success()
    }

    func retryFailedKeep(in dataStore: DataStore) async {
        guard let draft = failedDraft else { return }
        await keep(draft, in: dataStore)
    }

    /// Hides the pill, and gives up on a failed table.
    func clearProgress() {
        progress = nil
        failedDraft = nil
    }

    func update(_ moment: TableMoment) {
        guard let index = moments.firstIndex(where: { $0.id == moment.id }) else { return }
        moments[index] = moment
        persist()
    }

    /// Takes a dish off its table. The caller unlogs the diary entry; a
    /// table with nothing left on it goes too.
    func remove(dishID: UUID, from momentID: UUID) {
        guard let index = moments.firstIndex(where: { $0.id == momentID }) else { return }
        if let filename = moments[index].dishes.first(where: { $0.id == dishID })?.stickerFilename {
            deleteFile(filename)
        }
        moments[index].dishes.removeAll { $0.id == dishID }
        if moments[index].dishes.isEmpty { moments.remove(at: index) }
        persist()
    }

    /// Drops the plate whose diary entry was deleted, wherever it sits,
    /// so its cut-out doesn't outlive the meal.
    func removeDish(id: UUID) {
        guard let moment = moments.first(where: { $0.dishes.contains { $0.id == id } }) else { return }
        remove(dishID: id, from: moment.id)
    }

    /// "Delete all data" — cut-outs are photos of the user's meals and
    /// must not survive an erase.
    func deleteAll() {
        moments = []
        progress = nil
        failedDraft = nil
        stickers.removeAllObjects()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    // MARK: - Disk

    private var momentsURL: URL? { directory?.appendingPathComponent("moments.json") }

    private func load() -> [TableMoment] {
        guard let url = momentsURL, let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder().decode([TableMoment].self, from: data)
        } catch {
            AppLog.persistence.error("Table moments unreadable: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func persist() {
        guard let url = momentsURL, ensureDirectory() else { return }
        do {
            try JSONEncoder().encode(moments).write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            AppLog.persistence.error("Table moments not saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func writeSticker(_ image: UIImage) async -> String? {
        guard let directory, ensureDirectory() else { return nil }
        let filename = "dish-\(UUID().uuidString).png"
        let url = directory.appendingPathComponent(filename)
        let stored = Self.downscaled(image)
        let written = await Task.detached(priority: .utility) { () -> Bool in
            guard let data = stored.pngData() else { return false }
            return (try? data.write(to: url, options: [.atomic, .completeFileProtection])) != nil
        }.value
        guard written else { return nil }
        stickers.setObject(stored, forKey: filename as NSString)
        return filename
    }

    private func deleteFile(_ filename: String) {
        stickers.removeObject(forKey: filename as NSString)
        guard let url = directory?.appendingPathComponent(filename) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func ensureDirectory() -> Bool {
        guard let directory else { return false }
        if FileManager.default.fileExists(atPath: directory.path) { return true }
        return (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil
    }

    private static func downscaled(_ image: UIImage) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        guard longest > stickerMaxEdge else { return image }
        let ratio = stickerMaxEdge / longest
        let target = CGSize(width: (pixelWidth * ratio).rounded(), height: (pixelHeight * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
