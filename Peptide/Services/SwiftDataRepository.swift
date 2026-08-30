import CloudKit
import CoreData
import Foundation
import SwiftData

/// User-facing iCloud sync condition, derived at container creation
/// and refined on demand via `CKAccountStatus`. `.unavailable` covers
/// container-open failures with an account present (quota, network,
/// CloudKit outage); `.restricted` is parental controls / MDM.
enum CloudSyncState: Sendable {
    case active
    case noAccount
    case restricted
    case unavailable
}

/// SwiftData-backed persistence for protocols, entries, and profile.
/// Widget data stays in PersistenceService (requires App Groups / shared container).
@MainActor
final class SwiftDataRepository {
    static let shared = SwiftDataRepository()

    private var container: ModelContainer?

    /// True when the on-disk store could not be opened and we fell back to an
    /// in-memory container. The app remains usable, but mutations won't persist
    /// across launches. DataStore surfaces this to the user via `lastError`.
    private(set) var isUsingFallbackStore = false

    /// True when neither on-disk nor in-memory containers could be created.
    /// All reads return empty and writes are no-ops. DataStore surfaces this
    /// to the user via `lastError`.
    private(set) var isInoperable = false

    private var context: ModelContext? {
        container?.mainContext
    }

    /// Snapshot of the iCloud identity token observed at container
    /// creation. When the user signs out of iCloud or switches accounts
    /// at the system level, this token changes and Apple's CloudKit
    /// docs require us to react — otherwise writes go to a container
    /// whose identity is stale and the next account's local view
    /// silently inherits the previous account's local data.
    private var lastObservedIdentityToken: (any NSCoding & NSCopying & NSObjectProtocol)?

    private init() {
        let token = FileManager.default.ubiquityIdentityToken
        lastObservedIdentityToken = token
        let iCloudAvailable = token != nil
        let cloudFailureState: CloudSyncState = iCloudAvailable ? .unavailable : .noAccount
        if iCloudAvailable, let ck = Self.makeCloudContainer() {
            container = ck
            cloudSyncState = .active
        } else if let local = Self.makeLocalContainer() {
            container = local
            cloudSyncState = cloudFailureState
        } else if let inMemory = Self.makeInMemoryContainer() {
            container = inMemory
            isUsingFallbackStore = true
            cloudSyncState = cloudFailureState
        } else {
            container = nil
            isInoperable = true
            cloudSyncState = cloudFailureState
            assertionFailure("SwiftDataRepository: both on-disk and in-memory ModelContainer creation failed")
        }

        // Observe iCloud identity changes. When the token swaps, pause
        // writes and surface the change to DataStore so it can clear
        // in-memory state — otherwise account A's local data
        // becomes account B's local view on first launch under the
        // new identity.
        NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleIdentityChange()
            }
        }

        // Surface finished CloudKit *imports* to DataStore. SwiftData's
        // CloudKit mirroring runs on an NSPersistentCloudKitContainer we
        // never see directly, but its event notification is posted
        // process-wide, so observing with `object: nil` reaches it.
        // Without this, remote edits only became visible on relaunch or
        // the one pull-to-refresh — meanwhile the debounced save's
        // wholesale upsert of stale in-memory state silently reverted
        // the other device's writes (audit CloudKit P0-1). Only
        // successful, completed imports are forwarded; export/setup
        // events change nothing locally.
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { note in
            guard
                let event = note.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event,
                event.type == .import,
                event.endDate != nil,
                event.succeeded
            else { return }
            NotificationCenter.default.post(
                name: .peptideXCloudKitImportCompleted,
                object: nil
            )
        }
    }

    /// Compares the live identity token against the snapshot taken at
    /// container creation. If the user signed out / switched accounts,
    /// tears down the old container and rebuilds for the new identity
    /// before posting a notification — DataStore listens and reloads
    /// from the new container. The previous implementation only set
    /// `isInoperable = true` and never recreated the container, which
    /// left persistence permanently degraded for the rest of the
    /// process lifetime.
    @MainActor
    private func handleIdentityChange() {
        let current = FileManager.default.ubiquityIdentityToken
        let prev = lastObservedIdentityToken
        let isSame: Bool = {
            switch (prev, current) {
            case (nil, nil): return true
            case let (a?, b?): return a.isEqual(b)
            default: return false
            }
        }()
        guard !isSame else { return }
        lastObservedIdentityToken = current
        AppLog.swiftData.error(
            "iCloud identity changed; tearing down container and re-initializing"
        )

        // Pause writes during the swap so any in-flight save attempt
        // doesn't see a half-initialised container.
        isInoperable = true
        container = nil
        isUsingFallbackStore = false
        let cloudFailureState: CloudSyncState = current != nil ? .unavailable : .noAccount
        cloudSyncState = cloudFailureState

        // Rebuild — same fallback chain as `init`.
        if current != nil, let ck = Self.makeCloudContainer() {
            container = ck
            cloudSyncState = .active
            isInoperable = false
        } else if let local = Self.makeLocalContainer() {
            container = local
            isInoperable = false
        } else if let inMemory = Self.makeInMemoryContainer() {
            container = inMemory
            isUsingFallbackStore = true
            isInoperable = false
        } else {
            // Genuinely couldn't open anything — leave isInoperable=true.
            // DataStore will see empty loads + writes will no-op, which
            // is the safest available state until the user relaunches.
            AppLog.swiftData.error("Container re-init failed after identity change; reads will be empty")
        }

        // Notify DataStore — by the time this fires, the container has
        // already swapped, so `reloadFromDisk` in the observer reads
        // from the new identity's store.
        NotificationCenter.default.post(name: .peptideXiCloudIdentityChanged, object: nil)
    }

    private(set) var cloudSyncState: CloudSyncState = .unavailable

    /// Kept for existing call sites (DataStore) — derived from
    /// `cloudSyncState` so the two can't disagree.
    var isCloudSyncEnabled: Bool { cloudSyncState == .active }

    /// Container identifier — shared with `refinedCloudSyncState()`
    /// so the account check looks at the same container the store
    /// syncs to.
    private static let cloudContainerID = "iCloud.com.peptidesai.app"

    /// Refines a non-active state via `CKAccountStatus` so the
    /// Profile indicator can tell "no iCloud account" apart from
    /// "iCloud restricted" and from a genuine container failure
    /// (quota, network, CloudKit outage) — audit 3.1.
    func refinedCloudSyncState() async -> CloudSyncState {
        guard cloudSyncState != .active else { return .active }
        let status = try? await CKContainer(identifier: Self.cloudContainerID).accountStatus()
        switch status {
        case .noAccount: return .noAccount
        case .restricted: return .restricted
        default: return cloudSyncState
        }
    }

    /// Versioned schema declaration used by every container path
    /// below. Plan D scaffold — see `PeptideAtlasSchema.swift` for
    /// the V2 declaration and the migration plan template that a
    /// future V3 will extend.
    private static var versionedSchema: Schema {
        Schema(versionedSchema: PeptideAtlasSchemaV2.self)
    }

    private static func makeCloudContainer() -> ModelContainer? {
        do {
            let config = ModelConfiguration(cloudKitDatabase: .private(cloudContainerID))
            let container = try ModelContainer(
                for: versionedSchema,
                migrationPlan: PeptideAtlasMigrationPlan.self,
                configurations: config
            )
            AppLog.swiftData.info("Using CloudKit-backed store")
            return container
        } catch {
            AppLog.swiftData.error("CloudKit store failed, falling back to local: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func makeLocalContainer() -> ModelContainer? {
        do {
            return try ModelContainer(
                for: versionedSchema,
                migrationPlan: PeptideAtlasMigrationPlan.self
            )
        } catch {
            AppLog.swiftData.error("Failed to create persistent ModelContainer: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func makeInMemoryContainer() -> ModelContainer? {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try ModelContainer(
                for: versionedSchema,
                migrationPlan: PeptideAtlasMigrationPlan.self,
                configurations: config
            )
        } catch {
            AppLog.swiftData.error("Failed to create in-memory ModelContainer: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Test Support

    #if DEBUG
    /// Test-only: direct context access so tests can assert on and
    /// construct row-level fixtures (e.g. duplicate profile rows) that
    /// the public API rightly refuses to create.
    var contextForTesting: ModelContext? { context }
    #endif

    /// Replaces the container with an in-memory store. Call in test setUp only.
    func configureForTesting() {
        container = Self.makeInMemoryContainer()
        isUsingFallbackStore = false
        isInoperable = container == nil
        commitDidFail = false
        #if DEBUG
        forceCommitFailureForTesting = false
        #endif
    }

    /// Discards uncommitted changes pending on the context. The
    /// migration rollback path needs this before `deleteAll()`: after a
    /// failed commit the imported objects are still *pending* inserts,
    /// which a bulk delete (store-level) doesn't touch — the cleanup's
    /// own save would then persist exactly the partial import the
    /// rollback exists to remove.
    func discardPendingChanges() {
        context?.rollback()
    }

    /// Removes all records. Call in test tearDown only.
    func deleteAll() {
        guard let context else { return }
        do {
            try context.delete(model: StoredProtocol.self)
            try context.delete(model: StoredEntry.self)
            try context.delete(model: StoredProfile.self)
            try context.delete(model: StoredWorkoutSession.self)
            try context.delete(model: StoredCustomExercise.self)
            try context.delete(model: StoredRoutine.self)
            try context.delete(model: StoredPersonalRecord.self)
            try context.save()
        } catch {
            AppLog.swiftData.error("deleteAll failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Protocols

    /// Legacy bulk-replace path. Treats `protocols` as the full
    /// canonical set: any stored row whose id is absent gets deleted.
    /// **Do not use from save-path code that may run while CloudKit
    /// is delivering remote inserts** — a remote-added row not yet
    /// reflected in the caller's in-memory set will be silently
    /// deleted (and the deletion propagates back to CloudKit).
    /// Migration + tests rely on the truncate-and-replace behaviour;
    /// the live save path should use `upsertProtocols` +
    /// `deleteProtocol(id:)` instead.
    func saveProtocols(_ protocols: [PeptideProtocol]) {
        guard let context else { return }
        let existing: [StoredProtocol]
        do {
            existing = try context.fetch(FetchDescriptor<StoredProtocol>())
        } catch {
            AppLog.swiftData.error("Fetch protocols failed: \(error.localizedDescription, privacy: .public)")
            existing = []
        }
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let inputIds = Set(protocols.map(\.id))

        for stored in existing where !inputIds.contains(stored.id) {
            context.delete(stored)
        }

        for proto in protocols {
            if let stored = existingById[proto.id] {
                do {
                    try stored.update(from: proto)
                } catch {
                    AppLog.swiftData.error("Update StoredProtocol failed: \(error.localizedDescription, privacy: .public)")
                }
            } else {
                do {
                    let stored = try StoredProtocol.make(from: proto)
                    context.insert(stored)
                } catch {
                    AppLog.swiftData.error("Insert StoredProtocol failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        commit()
    }

    /// Upsert-only protocol save — never deletes. Use this from the
    /// live DataStore save path; pair with explicit
    /// `deleteProtocol(id:)` calls at removal sites.
    func upsertProtocols(_ protocols: [PeptideProtocol]) {
        guard let context, !protocols.isEmpty else { return }
        let inputIds = protocols.map(\.id)
        let descriptor = FetchDescriptor<StoredProtocol>(
            predicate: #Predicate { inputIds.contains($0.id) }
        )
        let existingById: [UUID: StoredProtocol]
        do {
            let existing = try context.fetch(descriptor)
            existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        } catch {
            AppLog.swiftData.error("Fetch (upsert) protocols failed: \(error.localizedDescription, privacy: .public)")
            existingById = [:]
        }
        for proto in protocols {
            do {
                if let stored = existingById[proto.id] {
                    try stored.update(from: proto)
                } else {
                    context.insert(try StoredProtocol.make(from: proto))
                }
            } catch {
                AppLog.swiftData.error("Upsert StoredProtocol failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        commit()
    }

    func deleteProtocol(id: UUID) {
        guard let context else { return }
        let target = id
        let descriptor = FetchDescriptor<StoredProtocol>(
            predicate: #Predicate { $0.id == target }
        )
        do {
            for stored in try context.fetch(descriptor) {
                context.delete(stored)
            }
            commit()
        } catch {
            AppLog.swiftData.error("Delete StoredProtocol failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadProtocols() -> [PeptideProtocol] {
        guard let context else { return [] }
        let descriptor = FetchDescriptor<StoredProtocol>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let stored: [StoredProtocol]
        do {
            stored = try context.fetch(descriptor)
        } catch {
            AppLog.swiftData.error("Load protocols failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        return stored.compactMap {
            do {
                return try $0.toPeptideProtocol()
            } catch {
                AppLog.swiftData.error("Decode StoredProtocol failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    // MARK: - Entries

    /// Legacy bulk-replace path — see `saveProtocols` doc comment for
    /// the CloudKit-data-loss warning. Tests + migration only.
    func saveEntries(_ entries: [ProtocolEntry]) {
        guard let context else { return }
        let existing: [StoredEntry]
        do {
            existing = try context.fetch(FetchDescriptor<StoredEntry>())
        } catch {
            AppLog.swiftData.error("Fetch entries failed: \(error.localizedDescription, privacy: .public)")
            existing = []
        }
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let inputIds = Set(entries.map(\.id))

        for stored in existing where !inputIds.contains(stored.id) {
            context.delete(stored)
        }

        for entry in entries {
            if let stored = existingById[entry.id] {
                do {
                    try stored.update(from: entry)
                } catch {
                    AppLog.swiftData.error("Update StoredEntry failed: \(error.localizedDescription, privacy: .public)")
                }
            } else {
                do {
                    let stored = try StoredEntry.make(from: entry)
                    context.insert(stored)
                } catch {
                    AppLog.swiftData.error("Insert StoredEntry failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        commit()
    }

    /// Upsert-only entry save — never deletes. Used by the live save
    /// path; pair with explicit `deleteEntries(ids:)` calls at the
    /// removal sites.
    func upsertEntries(_ entries: [ProtocolEntry]) {
        guard let context, !entries.isEmpty else { return }
        let inputIds = entries.map(\.id)
        let descriptor = FetchDescriptor<StoredEntry>(
            predicate: #Predicate { inputIds.contains($0.id) }
        )
        let existingById: [UUID: StoredEntry]
        do {
            let existing = try context.fetch(descriptor)
            existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        } catch {
            AppLog.swiftData.error("Fetch (upsert) entries failed: \(error.localizedDescription, privacy: .public)")
            existingById = [:]
        }
        for entry in entries {
            do {
                if let stored = existingById[entry.id] {
                    try stored.update(from: entry)
                } else {
                    context.insert(try StoredEntry.make(from: entry))
                }
            } catch {
                AppLog.swiftData.error("Upsert StoredEntry failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        commit()
    }

    func deleteEntries(ids: Set<UUID>) {
        guard let context, !ids.isEmpty else { return }
        let targets = Array(ids)
        let descriptor = FetchDescriptor<StoredEntry>(
            predicate: #Predicate { targets.contains($0.id) }
        )
        do {
            for stored in try context.fetch(descriptor) {
                context.delete(stored)
            }
            commit()
        } catch {
            AppLog.swiftData.error("Delete StoredEntries failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadEntries() -> [ProtocolEntry] {
        fetchEntries(FetchDescriptor<StoredEntry>())
    }

    /// Recent-window fetch with the date filter pushed into SQLite —
    /// the cold-launch path uses this so first frame doesn't pay a
    /// full-table decode (one JSON `Peptide` decode per row) for
    /// history the UI can't show anyway. Mirrors
    /// `loadWorkoutSessions(startedBetween:)`.
    func loadEntries(onOrAfter cutoff: Date) -> [ProtocolEntry] {
        fetchEntries(FetchDescriptor<StoredEntry>(
            predicate: #Predicate { $0.date >= cutoff }
        ))
    }

    /// Complement of `loadEntries(onOrAfter:)` — the post-launch
    /// backfill that hydrates the long tail (exports, lifetime totals,
    /// multi-year streaks) without blocking first frame.
    func loadEntries(before cutoff: Date) -> [ProtocolEntry] {
        fetchEntries(FetchDescriptor<StoredEntry>(
            predicate: #Predicate { $0.date < cutoff }
        ))
    }

    /// ID-only projection for set-difference bookkeeping (backup
    /// import) — avoids materializing and JSON-decoding every row just
    /// to read UUIDs.
    func loadEntryIDs() -> [UUID] {
        guard let context else { return [] }
        var descriptor = FetchDescriptor<StoredEntry>()
        descriptor.propertiesToFetch = [\.id]
        do {
            return try context.fetch(descriptor).map(\.id)
        } catch {
            AppLog.swiftData.error("Load entry IDs failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Cheap lifetime entry count via `fetchCount` (no row
    /// materialization).
    func entryCount() -> Int {
        guard let context else { return 0 }
        do {
            return try context.fetchCount(FetchDescriptor<StoredEntry>())
        } catch {
            AppLog.swiftData.error("entryCount failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    private func fetchEntries(_ descriptor: FetchDescriptor<StoredEntry>) -> [ProtocolEntry] {
        guard let context else { return [] }
        let stored: [StoredEntry]
        do {
            stored = try context.fetch(descriptor)
        } catch {
            AppLog.swiftData.error("Load entries failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        return stored.compactMap {
            do {
                return try $0.toProtocolEntry()
            } catch {
                AppLog.swiftData.error("Decode StoredEntry failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    // MARK: - Profile

    /// Returns the canonical profile row, reconciling duplicates.
    /// Two devices that each ran the "no row yet → insert" branch before
    /// CloudKit converged leave two rows behind, and an unsorted
    /// `.first` fetch then flip-flops between them across launches.
    /// Reconciliation is deterministic: newest `updatedAt` wins; any
    /// split-area column the winner is missing is adopted from a loser
    /// (fills gaps only, never overwrites the winner's data); losers
    /// are deleted so every device converges on one row.
    private func canonicalProfileRow(in context: ModelContext) throws -> StoredProfile? {
        var rows = try context.fetch(FetchDescriptor<StoredProfile>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))
        guard rows.count > 1 else { return rows.first }
        AppLog.swiftData.warning("Reconciling \(rows.count, privacy: .public) StoredProfile rows to the newest")
        let winner = rows.removeFirst()
        for loser in rows {
            if winner.extensionData == nil { winner.extensionData = loser.extensionData }
            if winner.bodyMetricsData == nil { winner.bodyMetricsData = loser.bodyMetricsData }
            if winner.avatarImageData == nil { winner.avatarImageData = loser.avatarImageData }
            if winner.mealsData == nil { winner.mealsData = loser.mealsData }
            if winner.habitsData == nil { winner.habitsData = loser.habitsData }
            if winner.momentumData == nil { winner.momentumData = loser.momentumData }
            if winner.weightHistoryData == nil { winner.weightHistoryData = loser.weightHistoryData }
            if winner.labsData == nil { winner.labsData = loser.labsData }
            if winner.outcomesData == nil { winner.outcomesData = loser.outcomesData }
            if winner.foodLibraryData == nil { winner.foodLibraryData = loser.foodLibraryData }
            if winner.summariesData == nil { winner.summariesData = loser.summariesData }
            context.delete(loser)
        }
        commit()
        return winner
    }

    func saveProfile(_ profile: UserProfile) {
        guard let context else { return }
        let existing: StoredProfile?
        do {
            existing = try canonicalProfileRow(in: context)
        } catch {
            AppLog.swiftData.error("Fetch profile failed: \(error.localizedDescription, privacy: .public)")
            existing = nil
        }

        if let existing {
            do {
                try existing.update(from: profile)
            } catch {
                AppLog.swiftData.error("Update StoredProfile failed: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            do {
                let stored = try StoredProfile.make(from: profile)
                context.insert(stored)
            } catch {
                AppLog.swiftData.error("Insert StoredProfile failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        commit()
    }

    func loadProfile() -> UserProfile? {
        guard let context else { return nil }
        let stored: StoredProfile?
        do {
            stored = try canonicalProfileRow(in: context)
        } catch {
            AppLog.swiftData.error("Load profile failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard let stored else { return nil }
        do {
            return try stored.toUserProfile()
        } catch {
            AppLog.swiftData.error("Decode StoredProfile failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Workout sessions

    /// Upserts a single workout session. Used by the live workout
    /// screen as the user checks sets — one call per save event. The
    /// `commit()` call inside flushes the SwiftData context so widgets
    /// and the watch see the change without an extra round-trip.
    func upsertWorkoutSession(_ session: WorkoutSession) {
        guard let context else { return }
        let sessionID = session.id
        let descriptor = FetchDescriptor<StoredWorkoutSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        do {
            if let existing = try context.fetch(descriptor).first {
                try existing.update(from: session)
            } else {
                let stored = try StoredWorkoutSession.make(from: session)
                context.insert(stored)
            }
            commit()
        } catch {
            AppLog.swiftData.error("upsert workout session failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteWorkoutSession(id: UUID) {
        guard let context else { return }
        let targetID = id
        let descriptor = FetchDescriptor<StoredWorkoutSession>(
            predicate: #Predicate { $0.id == targetID }
        )
        do {
            for stored in try context.fetch(descriptor) {
                context.delete(stored)
            }
            commit()
        } catch {
            AppLog.swiftData.error("delete workout session failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Default fetch ceiling for workout history reads. TrainOverviewView
    /// only renders the last 3 sessions plus the current-month heatmap,
    /// so even a 200-cap reads more than any single surface uses while
    /// keeping the allocation bounded for power users with years of
    /// daily sessions.
    static let workoutHistoryFetchLimit: Int = 200

    func loadWorkoutSessions(limit: Int = SwiftDataRepository.workoutHistoryFetchLimit) -> [WorkoutSession] {
        guard let context else { return [] }
        var descriptor = FetchDescriptor<StoredWorkoutSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(1, limit)
        do {
            let stored = try context.fetch(descriptor)
            return stored.compactMap {
                do {
                    return try $0.toWorkoutSession()
                } catch {
                    AppLog.swiftData.error("Decode StoredWorkoutSession failed: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
        } catch {
            AppLog.swiftData.error("Load workout sessions failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Fetches one historical session by id. Used by `DataStore.deleteWorkout`
    /// to learn which exercises a session touched before the row goes away,
    /// so the affected personal records can be recomputed.
    func loadWorkoutSession(id: UUID) -> WorkoutSession? {
        guard let context else { return nil }
        var descriptor = FetchDescriptor<StoredWorkoutSession>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            return try context.fetch(descriptor).first.flatMap { try? $0.toWorkoutSession() }
        } catch {
            AppLog.swiftData.error("Load workout session by id failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Uncapped full-history fetch, oldest first. Exists for correctness
    /// passes that must see everything — PR recomputation after a deleted
    /// session would silently lose records older than the 200-row UI cap
    /// if it went through `loadWorkoutSessions(limit:)`. Not for render
    /// paths.
    func loadAllWorkoutSessions() -> [WorkoutSession] {
        guard let context else { return [] }
        let descriptor = FetchDescriptor<StoredWorkoutSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        do {
            let stored = try context.fetch(descriptor)
            return stored.compactMap {
                do {
                    return try $0.toWorkoutSession()
                } catch {
                    AppLog.swiftData.error("Decode StoredWorkoutSession (full) failed: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
        } catch {
            AppLog.swiftData.error("Load all workout sessions failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Cheap lifetime count of workout sessions via `fetchCount` (no row
    /// materialization). Used by the training-achievement check so it
    /// doesn't load the whole session table on a workout finish.
    func workoutSessionCount() -> Int {
        guard let context else { return 0 }
        do {
            return try context.fetchCount(FetchDescriptor<StoredWorkoutSession>())
        } catch {
            AppLog.swiftData.error("workoutSessionCount failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    /// Fetches workout sessions whose `startedAt` falls in the given
    /// half-open range. Used by `DataStore.workoutSummary` so the
    /// Today scroll's "movement" card doesn't fault the whole
    /// `StoredWorkoutSession` table on every render. The fetch uses a
    /// `#Predicate` so SwiftData can push the date window into the
    /// SQL backend instead of returning everything and filtering in
    /// memory.
    func loadWorkoutSessions(startedBetween range: Range<Date>) -> [WorkoutSession] {
        guard let context else { return [] }
        let lower = range.lowerBound
        let upper = range.upperBound
        var descriptor = FetchDescriptor<StoredWorkoutSession>(
            predicate: #Predicate { $0.startedAt >= lower && $0.startedAt < upper },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = SwiftDataRepository.workoutHistoryFetchLimit
        do {
            let stored = try context.fetch(descriptor)
            return stored.compactMap {
                do {
                    return try $0.toWorkoutSession()
                } catch {
                    AppLog.swiftData.error("Decode StoredWorkoutSession (windowed) failed: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
        } catch {
            AppLog.swiftData.error("Load windowed workout sessions failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Fetches the single in-progress session if one exists.
    /// `WorkoutSessionService` invariant: at most one session has
    /// `finishedAt == nil` at any time.
    func loadActiveWorkoutSession() -> WorkoutSession? {
        guard let context else { return nil }
        let descriptor = FetchDescriptor<StoredWorkoutSession>(
            predicate: #Predicate { $0.finishedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        do {
            return try context.fetch(descriptor).first.flatMap {
                try? $0.toWorkoutSession()
            }
        } catch {
            AppLog.swiftData.error("Load active workout failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Custom exercises

    func upsertCustomExercise(_ exercise: CustomExercise) {
        guard let context else { return }
        let id = exercise.id
        let descriptor = FetchDescriptor<StoredCustomExercise>(
            predicate: #Predicate { $0.id == id }
        )
        do {
            if let existing = try context.fetch(descriptor).first {
                try existing.update(from: exercise)
            } else {
                let stored = try StoredCustomExercise.make(from: exercise)
                context.insert(stored)
            }
            commit()
        } catch {
            AppLog.swiftData.error("upsert custom exercise failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteCustomExercise(id: String) {
        guard let context else { return }
        let exerciseID = id
        let descriptor = FetchDescriptor<StoredCustomExercise>(
            predicate: #Predicate { $0.id == exerciseID }
        )
        do {
            for stored in try context.fetch(descriptor) {
                context.delete(stored)
            }
            commit()
        } catch {
            AppLog.swiftData.error("delete custom exercise failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadCustomExercises() -> [CustomExercise] {
        guard let context else { return [] }
        let descriptor = FetchDescriptor<StoredCustomExercise>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        do {
            return try context.fetch(descriptor).compactMap {
                do {
                    return try $0.toCustomExercise()
                } catch {
                    AppLog.swiftData.error("Decode StoredCustomExercise failed: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
        } catch {
            AppLog.swiftData.error("Load custom exercises failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Routines

    func upsertRoutine(_ routine: Routine) {
        guard let context else { return }
        let routineID = routine.id
        let descriptor = FetchDescriptor<StoredRoutine>(
            predicate: #Predicate { $0.id == routineID }
        )
        do {
            if let existing = try context.fetch(descriptor).first {
                try existing.update(from: routine)
            } else {
                let stored = try StoredRoutine.make(from: routine)
                context.insert(stored)
            }
            commit()
        } catch {
            AppLog.swiftData.error("upsert routine failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteRoutine(id: UUID) {
        guard let context else { return }
        let targetID = id
        let descriptor = FetchDescriptor<StoredRoutine>(
            predicate: #Predicate { $0.id == targetID }
        )
        do {
            for stored in try context.fetch(descriptor) {
                context.delete(stored)
            }
            commit()
        } catch {
            AppLog.swiftData.error("delete routine failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadRoutines() -> [Routine] {
        guard let context else { return [] }
        // sortIndex is the user's drag order; updatedAt breaks ties so a
        // library that has never been reordered (every row at 0) still
        // reads most-recently-edited first.
        let descriptor = FetchDescriptor<StoredRoutine>(
            sortBy: [
                SortDescriptor(\.sortIndex),
                SortDescriptor(\.updatedAt, order: .reverse),
            ]
        )
        do {
            return try context.fetch(descriptor).compactMap {
                do {
                    return try $0.toRoutine()
                } catch {
                    AppLog.swiftData.error("Decode StoredRoutine failed: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
        } catch {
            AppLog.swiftData.error("Load routines failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Personal records

    func upsertPersonalRecord(_ record: PersonalRecord) {
        guard let context else { return }
        let id = record.exerciseID
        let descriptor = FetchDescriptor<StoredPersonalRecord>(
            predicate: #Predicate { $0.exerciseID == id }
        )
        do {
            if let existing = try context.fetch(descriptor).first {
                existing.update(from: record)
            } else {
                context.insert(StoredPersonalRecord.make(from: record))
            }
            commit()
        } catch {
            AppLog.swiftData.error("upsert PR failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadPersonalRecords() -> [PersonalRecord] {
        guard let context else { return [] }
        do {
            return try context.fetch(FetchDescriptor<StoredPersonalRecord>())
                .map { $0.toPersonalRecord() }
        } catch {
            AppLog.swiftData.error("Load PRs failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Removes the PR row for a given exercise. Used by tests to
    /// scrub state and (eventually) by a "reset this exercise"
    /// affordance the user might surface if their PR data gets
    /// corrupted. No-op when the row doesn't exist.
    func deletePersonalRecord(exerciseID: String) {
        guard let context else { return }
        let id = exerciseID
        let descriptor = FetchDescriptor<StoredPersonalRecord>(
            predicate: #Predicate { $0.exerciseID == id }
        )
        do {
            for row in try context.fetch(descriptor) {
                context.delete(row)
            }
            commit()
        } catch {
            AppLog.swiftData.error("delete PR failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - State

    var hasAnyData: Bool {
        guard let context else { return false }
        let descriptors: [() throws -> Int] = [
            { try context.fetchCount(FetchDescriptor<StoredProtocol>()) },
            { try context.fetchCount(FetchDescriptor<StoredEntry>()) },
            { try context.fetchCount(FetchDescriptor<StoredProfile>()) },
            { try context.fetchCount(FetchDescriptor<StoredWorkoutSession>()) },
            { try context.fetchCount(FetchDescriptor<StoredCustomExercise>()) },
            { try context.fetchCount(FetchDescriptor<StoredRoutine>()) },
        ]
        for descriptor in descriptors {
            do {
                if try descriptor() > 0 { return true }
            } catch {
                AppLog.swiftData.error("hasAnyData fetchCount failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return false
    }

    // MARK: - Save-failure tracking

    /// Set to `true` by `commit()` when a `context.save()` fails. The
    /// live DataStore save path resets it via `beginSaveBatch()` before
    /// a batch of upserts and reads it afterwards to surface a
    /// data-loss banner — previously these failures were only logged.
    private(set) var commitDidFail = false

    /// Resets the commit-failure flag at the start of a save batch.
    func beginSaveBatch() { commitDidFail = false }

    #if DEBUG
    /// Test-only: makes every `commit()` report failure without needing a
    /// genuinely broken store, so persistence-failure handling (banner,
    /// projection gating) is testable deterministically.
    var forceCommitFailureForTesting = false
    #endif

    // MARK: - Private

    @discardableResult
    private func commit() -> Bool {
        guard let context else { return false }
        #if DEBUG
        if forceCommitFailureForTesting {
            commitDidFail = true
            return false
        }
        #endif
        do {
            try context.save()
            return true
        } catch {
            AppLog.swiftData.error("context.save failed: \(error.localizedDescription, privacy: .public)")
            // One retry — covers transient file-protection / lock
            // races (e.g. a background save that beat the device
            // locking). A persistent failure (disk full, schema
            // conflict) still fails the retry and flags the batch.
            do {
                try context.save()
                AppLog.swiftData.info("context.save succeeded on retry")
                return true
            } catch {
                AppLog.swiftData.error("context.save retry failed: \(error.localizedDescription, privacy: .public)")
                commitDidFail = true
                return false
            }
        }
    }
}

extension Notification.Name {
    /// Posted when `FileManager.ubiquityIdentityToken` changes after
    /// the app was already running. DataStore observes this to clear
    /// in-memory state so account A's local data isn't visible to
    /// account B after a system-level iCloud account switch.
    static let peptideXiCloudIdentityChanged = Notification.Name("com.peptidesai.app.icloud.identity.changed")

    /// Posted after SwiftData's underlying CloudKit mirror finishes a
    /// successful import — i.e. rows written on another device just
    /// landed in the local store. DataStore observes this and refreshes
    /// its in-memory state (coalesced, and deferred around in-flight
    /// local saves) so remote edits become visible without a relaunch.
    static let peptideXCloudKitImportCompleted = Notification.Name("com.peptidesai.app.icloud.import.completed")
}
