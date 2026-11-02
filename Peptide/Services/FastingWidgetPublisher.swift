import Foundation
import WidgetKit

/// Writes `FastingWidgetSnapshot` to the App Group container for the
/// fasting widget and reloads only that widget. Skips the write when
/// nothing changed, so `FastingStore` can call it after every load
/// without spending the widget's reload budget.
@MainActor
final class FastingWidgetPublisher {
    static let shared = FastingWidgetPublisher()

    private var lastPublished: FastingWidgetSnapshot?

    private init() {}

    func publish(active fast: FastSession?) {
        let snapshot = Self.snapshot(for: fast)
        guard snapshot != lastPublished, let url = FastingWidgetSnapshot.fileURL else { return }
        do {
            // The widget reads this on the Lock Screen, while the device is locked.
            try snapshot.encoded().write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // Remembered only once written, so the next publish retries.
            AppLog.persistence.error("Fasting widget snapshot not written: \(error.localizedDescription, privacy: .public)")
            return
        }
        PersistenceService.excludeFromBackup(url)
        lastPublished = snapshot
        WidgetCenter.shared.reloadTimelines(ofKind: FastingWidgetSnapshot.widgetKind)
    }

    /// Removes the snapshot on data erase, so the widget falls back to
    /// "Not fasting" instead of a fast that no longer exists.
    func clear() {
        lastPublished = nil
        if let url = FastingWidgetSnapshot.fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: FastingWidgetSnapshot.widgetKind)
    }

    /// Pure mapping, internal for the tests.
    static func snapshot(for fast: FastSession?) -> FastingWidgetSnapshot {
        guard let fast, fast.isActive else { return .notFasting }
        return FastingWidgetSnapshot(active: FastingWidgetSnapshot.Active(
            fastId: fast.id,
            window: FastingWindow(startedAt: fast.startedAt, targetEnd: fast.targetEnd),
            protocolName: FastingLiveActivityService.protocolName(for: fast)
        ))
    }
}
