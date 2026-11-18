import Observation
import UIKit
import UserNotifications

/// What is in the fridge, freezer and cupboard, plus every product that
/// has ever gone in, so buying it again is a search and one tap.
///
/// One JSON file and a cut-out PNG per product, in Documents. Device-local
/// like the pantry and the table scans: what is in this kitchen's fridge
/// is not worth a CloudKit schema change.
@MainActor @Observable
final class FridgeStore {
    static let shared = FridgeStore()

    private struct Contents: Codable {
        var products: [FridgeProduct] = []
        var items: [FridgeItem] = []
        /// Nil in files saved while use-by days were stored at midnight.
        var daysAtNoon: Bool?
    }

    private(set) var products: [FridgeProduct] = []
    private(set) var items: [FridgeItem] = []

    /// Cut-outs are drawn at most ~200 pt across.
    static let photoMaxEdge: CGFloat = 640

    @ObservationIgnored private let directory: URL?
    @ObservationIgnored private let photos = NSCache<NSString, UIImage>()
    /// The latest PNG write per product. Each waits for the one before it,
    /// so the newest photo is the one left on disk.
    @ObservationIgnored private var photoWrites: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]
    @ObservationIgnored private var reminderTask: Task<Void, Never>?

    init(directory: URL? = FridgeStore.defaultDirectory) {
        self.directory = directory
        let contents = load()
        products = contents.products
        items = contents.daysAtNoon == true ? contents.items : contents.items.map { item in
            var item = item
            item.expiresOn = item.expiresOn.map { FridgeEngine.migratedDay($0, calendar: .current) }
            return item
        }
    }

    nonisolated static var defaultDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Fridge", isDirectory: true)
    }

    // MARK: - Reading

    var productsByID: [UUID: FridgeProduct] {
        Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func product(for item: FridgeItem) -> FridgeProduct? {
        products.first { $0.id == item.productID }
    }

    /// Recipe keys of everything at home and still good, for the recipe
    /// library, recipe pages and the weekly shopping list.
    var pantryKeys: Set<String> {
        FridgeEngine.pantryKeys(items: items, products: productsByID, now: .now, calendar: .current)
    }

    /// The cut-out, read from disk on a cache miss. For callers that need
    /// it synchronously (the shelf's physics scene); view bodies use
    /// `cachedPhoto(for:)` and `loadPhoto(for:)`.
    func photo(for product: FridgeProduct) -> UIImage? {
        if let cached = cachedPhoto(for: product) { return cached }
        guard product.hasPhoto, let url = photoURL(product.id),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        photos.setObject(image, forKey: Self.photoFilename(product.id) as NSString)
        return image
    }

    /// The cut-out if it is already in memory. Never touches the disk, so
    /// a view body can call it on every render.
    func cachedPhoto(for product: FridgeProduct) -> UIImage? {
        guard product.hasPhoto else { return nil }
        return photos.object(forKey: Self.photoFilename(product.id) as NSString)
    }

    /// Reads and decodes the cut-out off the main thread, then caches it,
    /// so a full fridge's first render doesn't decode every PNG on main.
    func loadPhoto(for product: FridgeProduct) async -> UIImage? {
        if let cached = cachedPhoto(for: product) { return cached }
        guard product.hasPhoto, let url = photoURL(product.id) else { return nil }
        let image = await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path)?.preparingForDisplay()
        }.value
        if let image { photos.setObject(image, forKey: Self.photoFilename(product.id) as NSString) }
        return image
    }

    private func photoURL(_ productID: UUID) -> URL? {
        directory?.appendingPathComponent(Self.photoFilename(productID))
    }

    // MARK: - Adding

    /// One product going in, for `add(_:)`.
    struct Addition {
        var product: FridgeProduct
        var photo: UIImage?
        var count = 1
        var place: FridgePlace?
        var expiresOn: Date?
    }

    /// Puts `count` of a product in, saving the product (or refreshing the
    /// saved one it matches) along the way. The same product with the same
    /// use-by day in the same place stacks onto one row.
    @discardableResult
    func add(
        _ product: FridgeProduct,
        photo: UIImage? = nil,
        count: Int = 1,
        place: FridgePlace? = nil,
        expiresOn: Date? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> FridgeItem {
        let addition = Addition(product: product, photo: photo, count: count, place: place, expiresOn: expiresOn)
        let item = insert(addition, now: now, calendar: calendar)
        changed()
        return item
    }

    /// Puts a whole scan in with one write to disk and one reminder pass.
    func add(_ additions: [Addition], now: Date = .now, calendar: Calendar = .current) {
        guard !additions.isEmpty else { return }
        for addition in additions {
            insert(addition, now: now, calendar: calendar)
        }
        changed()
    }

    @discardableResult
    private func insert(_ addition: Addition, now: Date, calendar: Calendar) -> FridgeItem {
        let place = addition.place ?? addition.product.place
        let saved = save(addition.product, photo: addition.photo, place: place, expiresOn: addition.expiresOn, now: now, calendar: calendar)
        let day = addition.expiresOn.map { FridgeEngine.storedDay($0, calendar: calendar) }
        let count = max(1, addition.count)
        if let index = items.firstIndex(where: {
            $0.productID == saved.id && $0.place == place
                && $0.expiresOn.map(calendar.startOfDay) == day.map(calendar.startOfDay)
        }) {
            items[index].count += count
            return items[index]
        }
        let item = FridgeItem(productID: saved.id, count: count, place: place, expiresOn: day, addedAt: now)
        items.append(item)
        return item
    }

    /// Stores the product under the saved one it matches (same id, barcode,
    /// or name and brand), learning how long it keeps in `place` from
    /// `expiresOn`.
    private func save(
        _ product: FridgeProduct,
        photo: UIImage?,
        place: FridgePlace,
        expiresOn: Date?,
        now: Date,
        calendar: Calendar
    ) -> FridgeProduct {
        var product = product
        if let existing = products.first(where: { Self.isSame($0, product) }) {
            product.id = existing.id
            product.hasPhoto = existing.hasPhoto
            product.imageURL = product.imageURL ?? existing.imageURL
            product.per100g = product.per100g ?? existing.per100g
            product.pantryKey = product.pantryKey ?? existing.pantryKey
            product.shelfDaysByPlace = Self.shelfDaysByPlace(of: existing)
                .merging(product.shelfDaysByPlace ?? [:]) { _, new in new }
            product.shelfDays = nil
            product.amount = product.amount ?? existing.amount
        }
        product.lastAddedAt = now
        if let expiresOn,
           let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: expiresOn)).day,
           days > 0 {
            product.learnShelfLife(days, in: place)
        }
        if let photo, writePhoto(photo, for: product.id) { product.hasPhoto = true }
        if let index = products.firstIndex(where: { $0.id == product.id }) {
            products[index] = product
        } else {
            products.append(product)
        }
        return product
    }

    /// The saved product's shelf lives per place, with one saved before
    /// they were kept per place filed under the place it was saved in, not
    /// the place it is being moved to.
    private static func shelfDaysByPlace(of existing: FridgeProduct) -> [FridgePlace: Int] {
        var byPlace = existing.shelfDaysByPlace ?? [:]
        if let legacy = existing.shelfDays, byPlace[existing.place] == nil { byPlace[existing.place] = legacy }
        return byPlace
    }

    static func isSame(_ lhs: FridgeProduct, _ rhs: FridgeProduct) -> Bool {
        if lhs.id == rhs.id { return true }
        if let barcode = lhs.barcode, !barcode.isEmpty { return barcode == rhs.barcode }
        return rhs.barcode == nil
            && lhs.name.compare(rhs.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            && (lhs.brand ?? "").lowercased() == (rhs.brand ?? "").lowercased()
    }

    // MARK: - Changing

    func update(_ item: FridgeItem, calendar: Calendar = .current) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var item = item
        item.expiresOn = item.expiresOn.map { FridgeEngine.storedDay($0, calendar: calendar) }
        items[index] = item
        changed()
    }

    func update(_ product: FridgeProduct, photo: UIImage? = nil) {
        guard let index = products.firstIndex(where: { $0.id == product.id }) else { return }
        var product = product
        if let photo, writePhoto(photo, for: product.id) { product.hasPhoto = true }
        products[index] = product
        changed()
    }

    /// Eaten or cooked: one fewer, and the row goes with the last one.
    func useOne(_ itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        if items[index].count > 1 {
            items[index].count -= 1
        } else {
            items.remove(at: index)
        }
        changed()
    }

    /// Thrown out or gone: the whole row. The product stays saved.
    func remove(_ itemID: UUID) {
        items.removeAll { $0.id == itemID }
        changed()
    }

    /// Forgets a saved product, along with anything of it still in.
    func forget(_ productID: UUID) {
        items.removeAll { $0.productID == productID }
        products.removeAll { $0.id == productID }
        photoWrites.removeValue(forKey: productID)?.task.cancel()
        deleteFile(Self.photoFilename(productID))
        changed()
    }

    /// "Delete all data" — the photos are of the user's kitchen.
    func deleteAll() {
        products = []
        items = []
        photos.removeAllObjects()
        photoWrites.values.forEach { $0.task.cancel() }
        photoWrites = [:]
        reminderTask?.cancel()
        if let directory { try? FileManager.default.removeItem(at: directory) }
        FridgeReminderScheduler.cancel()
    }

    private func changed() {
        persist()
        scheduleReminders()
    }

    // MARK: - Reminders

    /// Rolls the use-by reminder forward from what is in now. Called on
    /// every change and whenever the app comes forward or leaves, since the
    /// one pending reminder covers only the soonest day.
    func reconcileReminders() async {
        await scheduleReminders().value
    }

    /// Asks for notifications the first time a dated item goes in, and
    /// schedules on a yes; a no keeps the coloured badges doing the reminding.
    func askForRemindersIfNeeded() async {
        guard items.contains(where: { $0.expiresOn != nil }),
              await NotificationService.shared.checkAuthorization() == .notDetermined,
              await NotificationService.shared.requestAuthorization() else { return }
        await reconcileReminders()
    }

    /// One pass at a time, newest wins: each waits for the one before, and
    /// a pass replaced before it starts is skipped, so an older snapshot can
    /// never land after a newer one.
    @discardableResult
    private func scheduleReminders() -> Task<Void, Never> {
        let previous = reminderTask
        previous?.cancel()
        let items = items
        let products = productsByID
        let task = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await FridgeReminderScheduler.reconcile(items: items, products: products)
        }
        reminderTask = task
        return task
    }

    // MARK: - Disk

    private var contentsURL: URL? { directory?.appendingPathComponent("fridge.json") }

    private static func photoFilename(_ productID: UUID) -> String {
        "product-\(productID.uuidString).png"
    }

    private func load() -> Contents {
        guard let url = contentsURL, let data = try? Data(contentsOf: url) else { return Contents() }
        do {
            return try JSONDecoder().decode(Contents.self, from: data)
        } catch {
            AppLog.persistence.error("Fridge unreadable: \(error.localizedDescription, privacy: .public)")
            return Contents()
        }
    }

    private func persist() {
        guard let url = contentsURL, ensureDirectory() else { return }
        do {
            try JSONEncoder().encode(Contents(products: products, items: items, daysAtNoon: true))
                .write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            AppLog.persistence.error("Fridge not saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Caches the downscaled cut-out at once and encodes and writes the PNG
    /// off the main actor, as `TableMomentStore.writeSticker` does. A write
    /// that fails is reported back by `photoWriteFinished`.
    private func writePhoto(_ image: UIImage, for productID: UUID) -> Bool {
        guard let url = photoURL(productID), ensureDirectory() else { return false }
        let stored = Self.downscaled(image)
        photos.setObject(stored, forKey: Self.photoFilename(productID) as NSString)
        let previous = photoWrites[productID]?.task
        let token = UUID()
        let task = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            let saved = await Task.detached(priority: .utility) { Self.writePNG(stored, to: url) }.value
            self?.photoWriteFinished(productID, token: token, url: url, saved: saved)
        }
        photoWrites[productID] = (token, task)
        return true
    }

    /// A photo written for a product that was forgotten meanwhile is
    /// removed. A failed write leaves `hasPhoto` matching what is on disk,
    /// so a relaunch doesn't promise a photo that isn't there.
    private func photoWriteFinished(_ productID: UUID, token: UUID, url: URL, saved: Bool) {
        let isLatest = photoWrites[productID]?.token == token
        if isLatest { photoWrites.removeValue(forKey: productID) }
        guard let index = products.firstIndex(where: { $0.id == productID }) else {
            if saved { try? FileManager.default.removeItem(at: url) }
            return
        }
        guard !saved, isLatest, !Task.isCancelled else { return }
        photos.removeObject(forKey: Self.photoFilename(productID) as NSString)
        let onDisk = FileManager.default.fileExists(atPath: url.path)
        guard products[index].hasPhoto != onDisk else { return }
        products[index].hasPhoto = onDisk
        changed()
    }

    nonisolated private static func writePNG(_ image: UIImage, to url: URL) -> Bool {
        guard let data = image.pngData() else { return false }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            AppLog.persistence.error("Fridge photo not saved: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Waits for every pending photo write. For tests.
    func photoWritesSettled() async {
        while let pending = photoWrites.values.first?.task {
            await pending.value
        }
    }

    private func deleteFile(_ filename: String) {
        photos.removeObject(forKey: filename as NSString)
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
        guard longest > photoMaxEdge else { return image }
        let ratio = photoMaxEdge / longest
        let target = CGSize(width: (pixelWidth * ratio).rounded(), height: (pixelHeight * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
