import Foundation

/// The user's fasting history, held in memory so the Meals card and the
/// fasting sheet read one array and re-render together. Writes go
/// straight through to `SwiftDataRepository`; at most one fast is open
/// at a time.
@MainActor @Observable
final class FastingStore {
    static let shared = FastingStore()

    /// Newest start first.
    private(set) var sessions: [FastSession] = []

    private var repository: SwiftDataRepository { .shared }

    private init() {}

    var active: FastSession? { sessions.first { $0.isActive } }

    var ended: [FastSession] { sessions.filter { !$0.isActive } }

    /// The plan and length the user last fasted with — what "Start"
    /// offers by default.
    var lastPlan: (plan: FastingProtocol, hours: Double) {
        guard let last = sessions.first else {
            return (.sixteen, FastingProtocol.sixteen.defaultFastingHours)
        }
        return (last.plan, last.targetHours)
    }

    /// Pulls history out of SwiftData and re-arms the end-of-fast
    /// reminder, Live Activity and widget, which a reinstall or another
    /// device may not have.
    func load() {
        sessions = repository.loadFasts()
        syncReminder()
        syncGlanceables()
    }

    @discardableResult
    func start(
        plan: FastingProtocol,
        targetHours: Double,
        remindsAtEnd: Bool,
        at now: Date = Date()
    ) -> FastSession {
        if let active { return active }
        let fast = FastSession(
            startedAt: now,
            targetHours: FastingEngine.clampedTargetHours(targetHours),
            plan: plan,
            remindsAtEnd: remindsAtEnd
        )
        save(fast)
        return fast
    }

    func end(at now: Date = Date()) {
        guard var fast = active else { return }
        fast.endedAt = max(now, fast.startedAt)
        save(fast)
    }

    /// Moves the open fast's start — for "I actually stopped eating at
    /// 19:30". Never into the future.
    func updateStart(_ date: Date, now: Date = Date()) {
        guard var fast = active else { return }
        fast.startedAt = min(date, now)
        save(fast)
    }

    func setReminder(_ enabled: Bool) {
        guard var fast = active else { return }
        fast.remindsAtEnd = enabled
        save(fast)
    }

    func delete(id: UUID) {
        repository.deleteFast(id: id)
        sessions.removeAll { $0.id == id }
        syncReminder()
        syncGlanceables()
    }

    // MARK: - Internals

    static let reminderID = "atlas.fasting.end"

    private func save(_ fast: FastSession) {
        repository.upsertFast(fast)
        sessions = repository.loadFasts()
        syncReminder()
        syncGlanceables()
    }

    /// The lock screen, Dynamic Island and widget follow the open fast
    /// through every start, end, cancel and edited start time.
    private func syncGlanceables() {
        FastingLiveActivityService.shared.reconcile(active: active)
        FastingWidgetPublisher.shared.publish(active: active)
    }

    /// One reminder slot, rescheduled from scratch on every change so an
    /// edited start time or a cancelled fast never leaves a stale buzz.
    private func syncReminder(now: Date = Date()) {
        NotificationService.cancelOneShot(id: Self.reminderID)
        guard let fast = active, fast.remindsAtEnd else { return }
        let remaining = FastingEngine.remaining(fast, at: now)
        guard remaining > 0 else { return }
        NotificationService.scheduleOneShot(
            id: Self.reminderID,
            title: String(localized: "Fast complete"),
            body: String(localized: "You reached your \(Int(fast.targetHours))-hour fasting goal. End the fast in Atlas when you eat."),
            after: remaining
        )
    }
}
