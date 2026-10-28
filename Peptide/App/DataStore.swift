import SwiftUI
import WidgetKit

@MainActor @Observable
final class DataStore {
    var protocols: [PeptideProtocol] {
        didSet {
            cacheVersion &+= 1
            revision &+= 1
            protocolsNeedSave = true
        }
    }
    var entries: [ProtocolEntry] {
        didSet {
            cacheVersion &+= 1
            revision &+= 1
            entriesNeedSave = true
        }
    }
    var profile: UserProfile {
        didSet {
            revision &+= 1
            profileNeedsSave = true
        }
    }
    var customPeptides: [Peptide] {
        didSet { peptideDatabaseCache = nil }
    }

    /// False while custom-peptides.json exists but couldn't be read.
    /// Saving then would replace the unread library with only what this
    /// session added.
    @ObservationIgnored private var customPeptidesReadable = true

    /// Observable counterpart to the private `cacheVersion`. Views key
    /// `.task(id:)` / `.onChange(of:)` off this to recompute a derived
    /// snapshot exactly once per mutation, instead of doing the work inline
    /// in `body` where it re-runs on every render pass.
    ///
    /// It's deliberately *not* `@ObservationIgnored` — that's the whole point.
    private(set) var revision: Int = 0

    /// Non-fatal banner message for the UI. Set when persistence falls back to
    /// in-memory storage so the user knows changes won't survive relaunch.
    var lastError: String?

    /// True when data is being synced to iCloud via CloudKit.
    var isCloudSyncEnabled: Bool { repo.isCloudSyncEnabled }

    /// True while the store is in App Store screenshot mode. All
    /// `performSaveNow()` calls short-circuit so demo data never
    /// touches disk. Real protocols / entries / profile sit
    /// untouched in the SwiftData store and on the JSON sidecars,
    /// ready to be restored the moment the user flips the toggle
    /// back off (see `ScreenshotMode.deactivate(in:)`).
    @ObservationIgnored
    var isEphemeral: Bool = false

    private let repo: SwiftDataRepository

    // MARK: - Cache (avoids recomputing expensive stats on every toggle)
    //
    // Each cached field stores the cacheVersion it was computed at. didSet on
    // `protocols`/`entries` increments cacheVersion automatically — readers
    // recompute when their stored version is stale. `bumpVersionIfDayChanged`
    // covers caches that depend on "today" (todayEntries, weeklyCompletion,
    // streaks) so they invalidate on midnight rollover.
    @ObservationIgnored private var cacheVersion: Int = 0
    @ObservationIgnored private var versionedDay: Date = Calendar.current.startOfDay(for: Date())

    /// When activation last pulled from HealthKit. A glance at Control
    /// Center or a Face ID prompt also re-activates the scene, and each
    /// pull republishes to the Watch and widgets.
    @ObservationIgnored private var lastHealthRefresh: Date?
    private static let healthRefreshInterval: TimeInterval = 5 * 60

    /// IDs scheduled for delete on the next save. Replaces the
    /// previous "bulk-replace and delete-missing" save path that
    /// silently dropped CloudKit-added records the local in-memory
    /// state hadn't picked up yet. Removal sites populate these;
    /// `performSaveNow` drains them.
    @ObservationIgnored private var pendingProtocolDeletions: Set<UUID> = []
    @ObservationIgnored private var pendingEntryDeletions: Set<UUID> = []

    // Per-collection dirty tracking. Every debounced save used to upsert
    // all protocols AND all entries AND re-encode the whole profile —
    // roughly ten JSON blobs, some of them unbounded (meal history, lab
    // values, weekly summaries) — for a single dose toggle. It also ran
    // in full on every background transition, whether or not anything
    // had changed.
    //
    // Set by the `didSet` observers above, cleared only once the batch
    // actually commits: if a save fails, the collection stays dirty and
    // the next save retries it, rather than the change being dropped.
    @ObservationIgnored private var protocolsNeedSave = false
    @ObservationIgnored private var entriesNeedSave = false
    @ObservationIgnored private var profileNeedsSave = false

    /// The profile as this device last read it from, or wrote it to, the
    /// store. Saves pass it as the baseline so a column this device
    /// didn't edit keeps whatever another device synced into it, rather
    /// than being reverted by in-memory state that predates the import.
    @ObservationIgnored private var persistedProfile: UserProfile?

    @ObservationIgnored private var _todayEntries: (version: Int, value: [ProtocolEntry])?
    @ObservationIgnored private var _currentStreak: (version: Int, value: Int)?
    @ObservationIgnored private var _totalDaysLogged: (version: Int, value: Int)?
    @ObservationIgnored private var _bestStreak: (version: Int, value: Int)?
    @ObservationIgnored private var _nextDose: (version: Int, value: ProtocolEntry?)?
    @ObservationIgnored private var _weeklyCompletion: (version: Int, value: [WeekDayStatus])?
    @ObservationIgnored private var _entriesByDay: (version: Int, value: [Date: [ProtocolEntry]])?
    @ObservationIgnored private var _activeEntriesByDay: (version: Int, value: [Date: [ProtocolEntry]])?
    @ObservationIgnored private var _stackPeptides: (version: Int, value: [Peptide])?
    @ObservationIgnored private var _stackWarnings: (version: Int, value: [StackRecommendationEngine.Warning])?
    @ObservationIgnored private var _stackRecommendations: (version: Int, value: [StackRecommendationEngine.Recommendation])?
    @ObservationIgnored private var _smartCycleSuggestions: (version: Int, value: [SmartCyclePlanner.Suggestion])?
    @ObservationIgnored private var _stackCompleteness: (version: Int, value: StackRecommendationEngine.StackCompleteness?)?
    @ObservationIgnored private var _cycleTransitions: (version: Int, value: [StackRecommendationEngine.CycleTransition])?
    @ObservationIgnored private var _topInsight: (version: Int, value: InsightEngine.Insight?)?

    private func bumpVersionIfDayChanged() {
        let today = Calendar.current.startOfDay(for: Date())
        if today != versionedDay {
            versionedDay = today
            cacheVersion &+= 1
        }
    }

    /// Entries keyed by start-of-day. Cached against `cacheVersion`, so all
    /// the per-day stats (currentStreak, totalDaysLogged, weeklyCompletion)
    /// share one O(n) group pass per mutation instead of re-filtering the
    /// entries array per day.
    var entriesByDay: [Date: [ProtocolEntry]] {
        if let cached = _entriesByDay, cached.version == cacheVersion { return cached.value }
        let grouped = entries.groupedByDay
        _entriesByDay = (cacheVersion, grouped)
        return grouped
    }

    /// `entriesByDay` filtered down to entries that belong to a currently
    /// active protocol. Streak math uses this so a user who paused a
    /// protocol mid-cycle isn't credited for days that no longer count,
    /// and historical views (e.g. `weeklyCompletion`) keep using the full
    /// `entriesByDay`.
    var activeEntriesByDay: [Date: [ProtocolEntry]] {
        // Cached against cacheVersion like `entriesByDay` — both
        // `currentStreak` and `bestStreak` call this, and they're
        // reached from view bodies, so the unfiltered version re-ran
        // the group + filter on every body pass. Protocol status
        // changes bump cacheVersion (same invariant the stack caches
        // rely on), so the key stays correct.
        if let cached = _activeEntriesByDay, cached.version == cacheVersion { return cached.value }
        let activeIds = Set(activeProtocols.map(\.id))
        let filtered = entriesByDay.compactMapValues { dayEntries -> [ProtocolEntry]? in
            let dayFiltered = dayEntries.filter { activeIds.contains($0.protocolId) }
            return dayFiltered.isEmpty ? nil : dayFiltered
        }
        _activeEntriesByDay = (cacheVersion, filtered)
        return filtered
    }

    init(seedSampleData: Bool = false) {
        // Initialize ALL stored properties first so Swift's two-phase init
        // is satisfied before any method calls on self.
        self.repo      = SwiftDataRepository.shared
        self.protocols = []
        self.entries   = []
        self.profile   = .fresh
        let storedCustomPeptides = DataStore.readCustomPeptides()
        self.customPeptides = storedCustomPeptides ?? []
        self.customPeptidesReadable = storedCustomPeptides != nil

        // Phase 2: self is fully initialized — safe to call methods.
        if repo.isAwaitingAccountDecision {
            // Held closed by an account change (A116) — not broken. The
            // app root asks the user what to do with the data.
            self.isAwaitingCloudAccountDecision = true
        } else if repo.isInoperable {
            // Never advise reinstalling: deleting the app erases any data
            // that hasn't reached iCloud yet.
            self.lastError = String(localized: "Atlas can't open its storage. Restart the app; if this keeps happening, contact support before deleting the app.")
        } else if repo.isUsingFallbackStore {
            self.lastError = String(localized: "Storage unavailable — changes won't be saved between launches.")
        }
        // Cold launch loads only the recent entry window synchronously —
        // every first-frame surface (Today, calendar month, 13-week
        // detail, streaks) reads inside it — and backfills the long
        // tail (exports, lifetime totals) right after, so a multi-year
        // history doesn't decode row-by-row before first frame.
        let entryWindowStart = Self.recentEntryWindowStart()
        let savedProtocols = repo.loadProtocols()
        let savedEntries   = repo.loadEntries(
            onOrAfter: entryWindowStart,
            resolvingFrom: Self.entryPeptideIndex(protocols: savedProtocols, customPeptides: customPeptides)
        )
        let savedProfile   = repo.loadProfile()
        let hasOlderEntries = repo.entryCount() > savedEntries.count

        let isReturningUser = !savedProtocols.isEmpty || !savedEntries.isEmpty || hasOlderEntries || savedProfile != nil
        if isReturningUser {
            // Returning user: recover what we can. Using || (not &&) so a single
            // corrupt record doesn't erase the user's entire dataset.
            self.protocols = savedProtocols
            self.entries   = savedEntries
            self.profile   = savedProfile ?? .fresh
            self.persistedProfile = savedProfile
            if let savedProfile {
                HealthSyncSettings.adoptSyncedNutritionFlag(savedProfile.healthKitNutritionEnabled)
                adoptDeviceHealthConnection()
            }
            // Everything above came off disk and is already persisted.
            // A synthesised `.fresh` profile is the exception: there's no
            // row for it yet, so it stays dirty until the first save
            // writes one.
            protocolsNeedSave = false
            entriesNeedSave = false
            profileNeedsSave = savedProfile == nil
            regenerateTodayEntries()
            // Plan C — drain the legacy `profile.workoutHistory` array
            // into the structured `StoredWorkoutSession` store the
            // Train tab reads from. Idempotent; flips a marker on the
            // profile so the migration is a no-op on every subsequent
            // launch.
            //
            // Persist whenever the marker transitions to true — that
            // includes the "no legacy entries to migrate" path where
            // we still need the marker stamped so the service doesn't
            // re-evaluate the (always-empty) array on every launch
            // forever. The save-after path is the only place the
            // marker actually reaches disk.
            let markerWasFalse = !profile.workoutLegacyMigrationCompleted
            _ = WorkoutLogMigrationService.migrateIfNeeded(profile: &profile, repository: repo)
            if markerWasFalse && profile.workoutLegacyMigrationCompleted {
                repo.saveProfile(profile)
                persistedProfile = profile
            }
            let goals = LegacyGoalMigration.migrate(goals: profile.goals, primaryGoal: profile.primaryGoal)
            let freezeDays = StreakFreezeService.migratingLegacyKeys(profile.streakFreezeDays)
            if goals.goals != profile.goals || goals.primaryGoal != profile.primaryGoal
                || freezeDays != profile.streakFreezeDays {
                profile.goals = goals.goals
                profile.primaryGoal = goals.primaryGoal
                profile.streakFreezeDays = freezeDays
                repo.saveProfile(profile)
                persistedProfile = profile
            }
        } else if seedSampleData {
            // Tests/previews: seed mock data
            let sampleProtocols = MockProtocols.all
            self.protocols = sampleProtocols
            self.entries = Self.generateInitialEntries(for: sampleProtocols)
            self.profile = MockProfile.current
            regenerateTodayEntries()
            // Seed path is one-shot bulk data; flush synchronously so a second
            // DataStore (e.g. in tests) sees the persisted state immediately
            // instead of waiting on the save debounce.
            performSaveNow()
        }
        // else: clean slate — already set to [] and .fresh above

        if hasOlderEntries {
            scheduleEntryBackfill(before: entryWindowStart)
        }
        if isReturningUser {
            seedAchievementsIfNeeded()
        } else if !seedSampleData {
            AchievementService.shared.markSeeded()
        }

        // If screenshot mode is currently enabled (set in
        // UserDefaults from a previous session before this cold
        // boot), swap in the demo seed before anyone reads state.
        // Done last so the swap also overrides any data that
        // hydrated from the repo branches above.
        ScreenshotMode.shared.bootstrapIfActive(in: self)

        // Self-register the current instance so App Intents and
        // other extension-style entry points can reach the running
        // store from outside the View hierarchy. Setting at the end
        // of init means callers never see a half-initialised store.
        Self.current = self

        // Clear the in-memory cache + reload from disk if the user
        // switches iCloud accounts mid-session. Without this the
        // previous account's protocols + entries would remain visible
        // to the new account until the next app launch.
        NotificationCenter.default.addObserver(
            forName: .peptideXiCloudIdentityChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleIdentityChange()
            }
        }

        // A launch while the device was locked (notification action,
        // Siri intent) may not have been able to read the library.
        NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.retryUnreadableCustomPeptides()
            }
        }

        // Ingest remote CloudKit changes. Before this observer existed,
        // rows written on another device reached memory only via one
        // pull-to-refresh or a relaunch — and the debounced save's
        // wholesale upsert of stale in-memory state could silently
        // revert the other device's writes in the meantime.
        NotificationCenter.default.addObserver(
            forName: .peptideXCloudKitImportCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleCloudImportRefresh()
            }
        }
    }

    /// Coalesces CloudKit-import notifications (they fire in bursts
    /// during a sync) into one `reloadFromDisk()`, deferred while a
    /// local change hasn't reached the store yet — the user's in-memory
    /// edits win locally and land via their own save; reloading over
    /// them mid-edit would drop keystrokes. If the store never goes
    /// quiet within the retry budget the refresh is skipped; the next
    /// import event catches up.
    @ObservationIgnored private var cloudImportRefreshTask: Task<Void, Never>?

    @MainActor
    private func scheduleCloudImportRefresh() {
        guard !isEphemeral else { return }
        cloudImportRefreshTask?.cancel()
        cloudImportRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            var attempts = 0
            while !Task.isCancelled, self?.hasUnsavedChanges == true, attempts < 10 {
                try? await Task.sleep(for: .seconds(1))
                attempts += 1
            }
            guard !Task.isCancelled,
                  let self,
                  !self.hasUnsavedChanges,
                  !self.isEphemeral
            else { return }
            AppLog.persistence.log("CloudKit import finished; refreshing in-memory state")
            self.reloadFromDisk()
        }
    }

    /// True while an in-memory change hasn't been committed: a debounced
    /// save is pending, or the last one failed and left state dirty.
    private var hasUnsavedChanges: Bool {
        pendingSaveTask != nil || protocolsNeedSave || entriesNeedSave || profileNeedsSave
            || !pendingProtocolDeletions.isEmpty || !pendingEntryDeletions.isEmpty
    }

    @MainActor
    private func handleIdentityChange() {
        AppLog.persistence.error("iCloud identity changed; clearing + reloading from new store")
        // Cancel any debounced save still in flight — it captured the
        // previous identity's in-memory state and, if it fired after
        // the container swap, would either be dropped silently or
        // written against the new account's store.
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        // Drop pending writes — they belong to the previous identity
        // and the next save's diff would otherwise commit them against
        // the new container.
        pendingProtocolDeletions.removeAll()
        pendingEntryDeletions.removeAll()
        // Clear first so any UI binding that runs between the clear
        // and the reload doesn't see a mix of the two identities'
        // data. didSet on protocols/entries auto-bumps cacheVersion
        // so every derived metric (streak, weeklyCompletion, etc.)
        // recomputes against the cleared state.
        protocols = []
        entries = []
        profile = .fresh
        WorkoutSessionService.shared.reloadActiveSession()
        isAwaitingCloudAccountDecision = repo.isAwaitingAccountDecision
        // SwiftDataRepository's identity handler swaps the container
        // BEFORE posting the notification, so loadProtocols / etc.
        // here read from the new identity's store. If the new
        // account has synced data this surfaces it immediately
        // instead of forcing the user through a relaunch to see
        // their own records.
        reloadFromDisk()
    }

    /// True while the store is held closed after an iCloud sign-out or
    /// account switch left the previous account's data on the device
    /// (A116). The app root asks the user to keep or remove it.
    private(set) var isAwaitingCloudAccountDecision = false

    /// Clears the prompt flag first, synchronously, so the alert can't
    /// flash back while the reload is pending. A failed removal keeps the
    /// store held (the hold persists, so the next launch asks again) and
    /// says so in the banner.
    func resolveCloudAccountChange(removingLocalData: Bool) {
        isAwaitingCloudAccountDecision = false
        // Nothing saved during the hold may land in the reopened store.
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        guard repo.resolveAccountChange(removingLocalData: removingLocalData) else {
            lastError = String(localized: "Atlas couldn't remove the previous account's data. Restart Atlas to try again.")
            return
        }
        // Reload now rather than after the notification's Task hop, so no
        // save can run against the reopened store with the cleared state.
        handleIdentityChange()
    }

    /// The currently-active `DataStore`, set by `init` and consumed
    /// by code that can't go through SwiftUI's `@Environment` —
    /// notably App Intents (Siri / Shortcuts / Action Button), which
    /// run in the app's process but outside the view tree.
    ///
    /// `Optional` rather than force-construct because intents can in
    /// theory fire before the SwiftUI scene's init completes the
    /// `_dataStore = State(...)` wrapping. Callers should fall
    /// through to "create a fresh one" (`DataStore()` reads from
    /// disk) on a nil read.
    @ObservationIgnored
    static var current: DataStore?

    // MARK: - Peptide Database

    /// The bundled catalog plus the user's own entries. Reads
    /// `PeptideDatabase.shared` lazily rather than caching it in a
    /// stored property — a stored one made `DataStore.init` decode
    /// ~930 KB of JSON on the main thread before the first frame.
    /// Merged once and reused until `customPeptides` changes; the
    /// catalog is 208 entries and this is read from list bodies.
    var peptideDatabase: [Peptide] {
        // Read before the cache check so observers still track
        // `customPeptides` on a cache hit.
        let custom = customPeptides
        if let cached = peptideDatabaseCache { return cached }
        let merged = PeptideDatabase.shared + custom
        peptideDatabaseCache = merged
        return merged
    }

    @ObservationIgnored private var peptideDatabaseCache: [Peptide]?

    /// Full records that stored dose snapshots resolve against (A379):
    /// the protocols' peptides — the records doses are generated from —
    /// then custom peptides. The bundled catalog is left out on purpose:
    /// this runs in `init`, and reading it there would put its ~930 KB
    /// decode back on the launch path.
    private var entryPeptideIndex: [UUID: Peptide] {
        Self.entryPeptideIndex(protocols: protocols, customPeptides: customPeptides)
    }

    private static func entryPeptideIndex(
        protocols: [PeptideProtocol], customPeptides: [Peptide]
    ) -> [UUID: Peptide] {
        EntryPeptideSnapshot.index(protocols.flatMap(\.peptides) + customPeptides)
    }

    func addCustomPeptide(_ peptide: Peptide) {
        customPeptides.append(peptide)
        retryUnreadableCustomPeptides()
        guard customPeptidesReadable else {
            lastError = Self.saveFailureMessage
            return
        }
        PersistenceService.shared.saveCustomPeptides(customPeptides)
        Haptics.success()
    }

    private static func readCustomPeptides() -> [Peptide]? {
        do {
            return try PersistenceService.shared.loadCustomPeptides()
        } catch {
            AppLog.persistence.error("Custom peptides unreadable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Re-reads a library that was unreadable at launch and keeps any
    /// peptide added since, writing the merge back.
    private func retryUnreadableCustomPeptides() {
        guard !customPeptidesReadable, let stored = Self.readCustomPeptides() else { return }
        let storedIDs = Set(stored.map(\.id))
        let addedSince = customPeptides.filter { !storedIDs.contains($0.id) }
        customPeptides = stored + addedSince
        customPeptidesReadable = true
        if !addedSince.isEmpty {
            PersistenceService.shared.saveCustomPeptides(customPeptides)
        }
    }

    // MARK: - Protocols

    var activeProtocols: [PeptideProtocol] {
        protocols.filter { $0.status == .active }
    }

    var pausedProtocols: [PeptideProtocol] {
        protocols.filter { $0.status == .paused }
    }

    var completedProtocols: [PeptideProtocol] {
        protocols.filter { $0.status == .completed }
    }

    func addProtocol(_ newProtocol: PeptideProtocol) {
        protocols.insert(newProtocol, at: 0)
        appendTodayEntries(for: newProtocol)
        save()
        rescheduleNotificationsIfEnabled()
        Haptics.success()
    }

    func deleteProtocol(id: UUID) {
        // Track the deletion explicitly so the save path can mirror
        // it through to SwiftData / CloudKit; the removeAll on the
        // arrays themselves is what the UI binds to.
        pendingProtocolDeletions.insert(id)
        let removedEntryIDs = entries.filter { $0.protocolId == id }.map(\.id)
        pendingEntryDeletions.formUnion(removedEntryIDs)
        protocols.removeAll { $0.id == id }
        entries.removeAll { $0.protocolId == id }
        save()
        rescheduleNotificationsIfEnabled()
    }

    /// Returns true on success, false when activating would exceed
    /// the free-tier 3-active-protocol cap. Callers should surface
    /// the paywall when this returns false on an .active transition.
    /// Was previously a `Void`-returning method with no gate, which
    /// let a free user stockpile paused protocols and resume them
    /// all to bypass the cap (audit Library P0.3).
    @discardableResult
    func updateProtocolStatus(id: UUID, to status: ProtocolStatus) -> Bool {
        guard let index = protocols.firstIndex(where: { $0.id == id }) else { return false }
        if status == .active, protocols[index].status != .active, activationExceedsFreeCap(id: id) {
            return false
        }
        let wasActive = protocols[index].status == .active
        protocols[index].status = status
        if status == .active {
            if !wasActive {
                CycleCompletionService.shared.restartGraceWindow(for: protocols[index])
            }
            appendTodayEntries(for: protocols[index])
        }
        save()
        rescheduleNotificationsIfEnabled()
        return true
    }

    /// Extends the cycle length of an active protocol by `weeks`. Used
    /// by the cycle-completion prompt's "Extend" action so the
    /// existing cycle's `startDate` stays put — the user just gets a
    /// longer cycle window. The completion prompt will re-fire when
    /// the extended window also ends.
    func extendProtocol(id: UUID, byWeeks weeks: Int) {
        guard let index = protocols.firstIndex(where: { $0.id == id }) else { return }
        protocols[index].cycleLengthWeeks = max(1, protocols[index].cycleLengthWeeks + weeks)
        save()
        rescheduleNotificationsIfEnabled()
    }

    /// Starts a fresh cycle for an existing protocol — same compounds,
    /// same schedule, `startDate` reset to today, status flipped back
    /// to `.active`. Used by the cycle-completion prompt's "Start new
    /// cycle" action. CycleMilestoneService keys on `startDate` so
    /// Day-7 / Day-30 / Complete prompts fire fresh for the new
    /// cycle without manual reset. Returns false, changing nothing, when
    /// re-activating an inactive protocol would exceed the free-tier cap
    /// — callers surface the paywall, as with `updateProtocolStatus`.
    @discardableResult
    func restartProtocol(id: UUID) -> Bool {
        guard let index = protocols.firstIndex(where: { $0.id == id }),
              protocols[index].status == .active || !activationExceedsFreeCap(id: id)
        else { return false }
        protocols[index].startDate = Calendar.current.startOfDay(for: Date())
        protocols[index].status = .active
        appendTodayEntries(for: protocols[index])
        save()
        rescheduleNotificationsIfEnabled()
        return true
    }

    private func activationExceedsFreeCap(id: UUID) -> Bool {
        let currentActive = protocols.filter {
            $0.status == .active && $0.id != id
        }.count
        guard StoreService.shared.requiresPro(activeProtocolCount: currentActive) else { return false }
        AppLog.storeKit.warning(
            "Protocol activation blocked — would exceed free-tier cap (\(currentActive, privacy: .public) already active)"
        )
        return true
    }

    /// Sweep called from `handleAppActivation` so cycles past the
    /// dismiss-or-grace threshold flip to `.completed` without user
    /// interaction. Logged at error level so the auto-completion is
    /// auditable in Console.app.
    func performCycleAutoCompletion() {
        let due = CycleCompletionService.shared.protocolsDueForAutoCompletion(in: protocols)
        guard !due.isEmpty else { return }
        for proto in due {
            AppLog.persistence.error(
                "Auto-completing protocol \(proto.id.uuidString, privacy: .public) — cycle ended"
            )
            if let index = protocols.firstIndex(where: { $0.id == proto.id }) {
                protocols[index].status = .completed
            }
            CycleCompletionService.shared.markAutoCompleted(proto)
        }
        save()
        rescheduleNotificationsIfEnabled()
    }

    // MARK: - Entries

    var todayEntries: [ProtocolEntry] {
        bumpVersionIfDayChanged()
        if let cached = _todayEntries, cached.version == cacheVersion { return cached.value }
        let calendar = Calendar.current
        let activeIds = Set(activeProtocols.map(\.id))
        let result = entries
            .filter { calendar.isDateInToday($0.date) && activeIds.contains($0.protocolId) }
            .sorted { $0.date < $1.date }
        _todayEntries = (cacheVersion, result)
        return result
    }

    func toggleEntry(_ entryId: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryId }) else { return }
        let becoming = !entries[index].completed
        entries[index].completed.toggle()
        if !becoming { entries[index].actualTime = nil }
        save()
        if becoming {
            doseWasTaken(entries[index])
        } else {
            reconcileDoseLiveActivities()
        }
    }

    /// A dose just became taken. Pushes that into any open lock-screen
    /// activity so the countdown stops and the "Logged" badge appears
    /// before auto-dismiss. One reminder covers every peptide a protocol
    /// doses at that minute, so its snoozes and its copy in Notification
    /// Center are withdrawn only once the whole slot is logged.
    private func doseWasTaken(_ entry: ProtocolEntry) {
        DoseLiveActivityService.shared.markCompleted(entry.id)
        let slotLogged = entries
            .filter {
                $0.protocolId == entry.protocolId
                    && Calendar.current.isDate($0.date, equalTo: entry.date, toGranularity: .minute)
            }
            .allSatisfy(\.completed)
        guard slotLogged else { return }
        Task { await NotificationService.shared.clearReminders(for: entry) }
    }

    /// Starts and ends lock-screen dose activities for active protocols
    /// only — the same set `todayEntries` shows — so a paused or
    /// completed protocol's dose never raises a "Time for X" activity.
    @discardableResult
    func reconcileDoseLiveActivities() -> [Task<Void, Never>] {
        let activeIds = Set(activeProtocols.map(\.id))
        return DoseLiveActivityService.shared.reconcile(
            entries: entries.filter { activeIds.contains($0.protocolId) }
        )
    }

    /// Idempotent completion setters for externally delivered commands
    /// (WatchConnectivity, widget intents). WCSession can deliver the same
    /// action twice — the Watch's `sendOrQueue` falls back to
    /// `transferUserInfo` when `sendMessage`'s error handler fires, which
    /// can happen after the phone already processed the message — so these
    /// only mutate when the entry is actually in the opposite state. A
    /// blind toggle would flip an already-completed dose back to
    /// incomplete on the duplicate delivery. Completion records when the
    /// dose was taken; undoing it clears that time.
    func markEntryComplete(_ entryId: UUID, at takenAt: Date) {
        guard let index = entries.firstIndex(where: { $0.id == entryId }),
              !entries[index].completed else { return }
        entries[index].actualTime = takenAt
        toggleEntry(entryId)
    }

    func markEntryIncomplete(_ entryId: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryId }),
              entries[index].completed else { return }
        toggleEntry(entryId)
    }

    func logDose(entryId: UUID, actualDose: String?, actualTime: Date?, injectionSite: String?, notes: String) {
        guard let index = entries.firstIndex(where: { $0.id == entryId }) else { return }
        let existing = entries[index]
        let wasCompleted = existing.completed
        entries[index] = ProtocolEntry(
            id: existing.id,
            protocolId: existing.protocolId,
            peptide: existing.peptide,
            date: existing.date,
            dose: existing.dose,
            notes: notes,
            completed: true,
            actualDose: actualDose?.nilIfEmpty,
            actualTime: actualTime,
            injectionSite: injectionSite
        )
        save()
        // The view that logged the dose plays its own haptic.
        if !wasCompleted { doseWasTaken(entries[index]) }
    }

    /// Removes a previously-logged dose — flips `completed` back to false
    /// AND clears the `actual*` capture fields so a future re-log starts
    /// from a clean slate. `toggleEntry` only flips completion and clears
    /// `actualTime`, which leaves stale `actualDose`/`injectionSite`/`notes`
    /// behind that the next render would have to ignore. Surfaces the
    /// Live Activity reconcile so a lock-screen dose that's now no
    /// longer logged returns to its pre-completion state.
    func unlogDose(entryId: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryId }) else { return }
        let existing = entries[index]
        entries[index] = ProtocolEntry(
            id: existing.id,
            protocolId: existing.protocolId,
            peptide: existing.peptide,
            date: existing.date,
            dose: existing.dose,
            notes: "",
            completed: false,
            actualDose: nil,
            actualTime: nil,
            injectionSite: nil
        )
        save()
        Haptics.warning()
        reconcileDoseLiveActivities()
    }

    func protocolsContaining(peptideId: UUID) -> [PeptideProtocol] {
        protocols.filter { proto in
            proto.peptides.contains { $0.id == peptideId }
        }
    }

    /// `schedule` keeps a moved peptide's own dose, times and cadence;
    /// it's stored as an override only when it differs from the
    /// destination's default.
    @discardableResult
    func addPeptide(
        _ peptide: Peptide,
        toProtocolId protocolId: UUID,
        schedule: ProtocolSchedule? = nil
    ) -> Bool {
        guard let index = protocols.firstIndex(where: { $0.id == protocolId }) else { return false }
        if protocols[index].peptides.contains(where: { $0.id == peptide.id }) { return false }

        let existing = protocols[index]
        var overrides = existing.peptideSchedules
        if let schedule, schedule != existing.schedule {
            overrides[peptide.id] = schedule
        }
        let updated = existing.with(peptides: existing.peptides + [peptide], peptideSchedules: overrides)
        protocols[index] = updated

        if updated.status == .active {
            let removed = entries.filter { entry in
                entry.protocolId == updated.id &&
                Calendar.current.isDateInToday(entry.date) &&
                entry.peptide.id == peptide.id
            }
            pendingEntryDeletions.formUnion(removed.map(\.id))
            entries.removeAll { entry in
                entry.protocolId == updated.id &&
                Calendar.current.isDateInToday(entry.date) &&
                entry.peptide.id == peptide.id
            }
            entries.append(contentsOf: Self.todayEntries(for: peptide, in: updated))
        }

        save()
        rescheduleNotificationsIfEnabled()
        Haptics.success()
        return true
    }

    func updateProtocol(
        id: UUID,
        name: String,
        peptides: [Peptide],
        schedule: ProtocolSchedule,
        peptideSchedules: [UUID: ProtocolSchedule] = [:],
        cycleLengthWeeks: Int,
        washoutWeeks: Int = 0,
        notes: String
    ) {
        guard let index = protocols.firstIndex(where: { $0.id == id }) else { return }

        // Drop overrides for peptides that are no longer in the protocol.
        let remainingIds = Set(peptides.map(\.id))
        let cleanedOverrides = peptideSchedules.filter { remainingIds.contains($0.key) }

        let existing = protocols[index]
        let updated = PeptideProtocol(
            id: id,
            name: name,
            peptides: peptides,
            schedule: schedule,
            peptideSchedules: cleanedOverrides,
            cycleLengthWeeks: cycleLengthWeeks,
            washoutWeeks: washoutWeeks,
            startDate: existing.startDate,
            status: existing.status,
            notes: notes,
            authorName: existing.authorName,
            authorHandle: existing.authorHandle,
            forkedFromStackId: existing.forkedFromStackId,
            createdAt: existing.createdAt
        )
        protocols[index] = updated
        if updated.status == .active, updated.cycleEndDay != existing.cycleEndDay {
            CycleCompletionService.shared.restartGraceWindow(for: updated)
        }

        // Regenerate today's entries, preserving any the user already
        // logged — see regenerateTodayEntriesPreservingLogs.
        regenerateTodayEntriesPreservingLogs(for: updated)

        save()
        rescheduleNotificationsIfEnabled()
    }

    /// Regenerates today's entries for `proto` after a schedule change,
    /// preserving any the user already completed or explicitly logged
    /// earlier today. Shared by `updateProtocol` and `setPeptideSchedule`.
    ///
    /// Without it, regenerating silently erased logged doses (completion,
    /// `actualDose`/`actualTime`, injection site, notes) AND added them to
    /// `pendingEntryDeletions` — so a CloudKit restore couldn't recover
    /// them either (Deep Audit III §1 + §11; `setPeptideSchedule` had the
    /// raw, unguarded version). Only the genuinely-discarded entries are
    /// marked for server-side deletion; the preserved ones are re-inserted
    /// and explicitly removed from the deletion set. A non-active protocol
    /// is left untouched — nothing to regenerate, nothing to delete.
    private func regenerateTodayEntriesPreservingLogs(for proto: PeptideProtocol) {
        guard proto.status == .active else { return }
        let id = proto.id
        let isToday: (ProtocolEntry) -> Bool = { entry in
            entry.protocolId == id && Calendar.current.isDateInToday(entry.date)
        }
        let toRemove = entries.filter(isToday)
        let completedToday = toRemove.filter(\.isLogged)
        let preservedIds = Set(completedToday.map(\.id))
        pendingEntryDeletions.formUnion(toRemove.filter { !preservedIds.contains($0.id) }.map(\.id))
        // A preserved entry is being kept in `entries`; it must never be
        // server-deleted, even if a prior pass queued its id.
        pendingEntryDeletions.subtract(preservedIds)
        entries.removeAll(where: isToday)

        // Append the regenerated schedule, then re-insert the user-logged
        // entries. When the new schedule already covers the same
        // (peptide, minute) slot, the user's logged entry wins.
        var merged = Self.generateTodayEntries(for: proto)
        for logged in completedToday {
            if let dupeIdx = merged.firstIndex(where: {
                $0.peptide.id == logged.peptide.id
                    && Calendar.current.isDate($0.date, equalTo: logged.date, toGranularity: .minute)
            }) {
                merged[dupeIdx] = logged
            } else {
                merged.append(logged)
            }
        }
        entries.append(contentsOf: merged)
    }

    /// Sets a per-peptide schedule override. Pass `nil` to remove it (peptide reverts to the
    /// protocol's default schedule). Regenerates today's entries and notifications.
    func setPeptideSchedule(protocolId: UUID, peptideId: UUID, schedule: ProtocolSchedule?) {
        guard let index = protocols.firstIndex(where: { $0.id == protocolId }) else { return }

        let existing = protocols[index]
        var overrides = existing.peptideSchedules
        if let schedule {
            overrides[peptideId] = schedule
        } else {
            overrides.removeValue(forKey: peptideId)
        }

        let updated = existing.with(peptideSchedules: overrides)
        protocols[index] = updated

        // Regenerate today's entries for this protocol so the change
        // takes effect immediately — preserving any the user already
        // logged (this path previously erased them, including from
        // CloudKit; Deep Audit III §1 + §11).
        regenerateTodayEntriesPreservingLogs(for: updated)

        save()
        rescheduleNotificationsIfEnabled()
        Haptics.impact(.light)
    }

    func entriesFor(protocolId: UUID, days: Int = 14) -> [ProtocolEntry] {
        let calendar = Calendar.current
        let cutoff = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        )
        return entries
            .filter { $0.protocolId == protocolId && $0.date >= cutoff }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Computed Stats

    var currentStreak: Int {
        bumpVersionIfDayChanged()
        if let cached = _currentStreak, cached.version == cacheVersion { return cached.value }
        let streak = StreakEngine.currentStreak(
            entriesByDay: activeEntriesByDay,
            frozenDayKeys: profile.streakFreezeDays
        )
        _currentStreak = (cacheVersion, streak)
        return streak
    }

    var totalDaysLogged: Int {
        if let cached = _totalDaysLogged, cached.version == cacheVersion { return cached.value }
        let result = entriesByDay.values.filter { dayEntries in
            dayEntries.contains(where: \.completed)
        }.count
        _totalDaysLogged = (cacheVersion, result)
        return result
    }

    var totalDoses: Int {
        entries.filter(\.completed).count
    }

    var bestStreak: Int {
        if let cached = _bestStreak, cached.version == cacheVersion { return cached.value }
        let best = StreakEngine.bestStreak(
            entriesByDay: activeEntriesByDay,
            frozenDayKeys: profile.streakFreezeDays
        )
        _bestStreak = (cacheVersion, best)
        return best
    }

    var weeklyCompletion: [WeekDayStatus] {
        bumpVersionIfDayChanged()
        if let cached = _weeklyCompletion, cached.version == cacheVersion { return cached.value }
        let calendar = Calendar.current
        let today = Date()
        let todayStart = calendar.startOfDay(for: today)

        let weekday = calendar.component(.weekday, from: today)
        let mondayOffset = weekday == 1 ? -6 : -(weekday - 2)
        guard let monday = calendar.date(byAdding: .day, value: mondayOffset, to: todayStart) else { return [] }

        let dayLabels = [String(localized: "Mon"), String(localized: "Tue"), String(localized: "Wed"), String(localized: "Thu"), String(localized: "Fri"), String(localized: "Sat"), String(localized: "Sun")]
        let grouped = entriesByDay

        let result = (0..<7).map { offset -> WeekDayStatus in
            let dayDate = calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
            let dayStart = calendar.startOfDay(for: dayDate)
            let isToday = dayStart == todayStart
            let isFuture = dayStart > todayStart

            let dayEntries = grouped[dayStart] ?? []

            let status: DayCompletionStatus
            if isFuture {
                status = .future
            } else if dayEntries.isEmpty {
                status = .noSchedule
            } else if isToday {
                let allDone = dayEntries.allSatisfy(\.completed)
                status = allDone ? .completed : .today
            } else {
                let completedCount = dayEntries.filter(\.completed).count
                if completedCount == dayEntries.count {
                    status = .completed
                } else if completedCount > 0 {
                    status = .partial
                } else {
                    status = .missed
                }
            }

            return WeekDayStatus(id: offset + 1, dayLabel: dayLabels[offset], status: status)
        }

        _weeklyCompletion = (cacheVersion, result)
        return result
    }

    var averageCompliance: Double {
        let now = Date()
        let pastEntries = entries.filter { $0.date <= now }
        let grouped = pastEntries.groupedByDay
        guard !grouped.isEmpty else { return 0 }

        let dailyCompliance = grouped.map { _, dayEntries in
            let completed = dayEntries.filter(\.completed).count
            return Double(completed) / Double(dayEntries.count)
        }

        return dailyCompliance.reduce(0, +) / Double(dailyCompliance.count)
    }

    /// Adherence (0…1) limited to a single protocol's entries. Used
    /// by the per-protocol share card so the "75%" figure on a
    /// shareable artifact actually reflects that protocol — the
    /// previous implementation used the global averageCompliance and
    /// shipped a misleading number when the user had multiple stacks
    /// (audit Sharing P1.6).
    ///
    /// Same definition as the protocol screen (`PeptideProtocol.adherence`),
    /// over the whole run since the protocol's start.
    func adherence(forProtocol id: UUID) -> Double {
        guard let proto = protocols.first(where: { $0.id == id }) else { return 0 }
        let calendar = Calendar.current
        let daysSinceStart = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: proto.startDate),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
        return proto.adherence(entries: entries, days: max(1, daysSinceStart + 1)) ?? 0
    }

    func complianceTrend(for range: Int) -> Double {
        let calendar = Calendar.current
        let now = Date()
        guard range > 1 else { return 0 }

        let halfPoint = range / 2
        guard let midCutoff = calendar.date(byAdding: .day, value: -halfPoint, to: now),
              let startCutoff = calendar.date(byAdding: .day, value: -range, to: now) else { return 0 }

        let recentEntries = entries.filter { $0.date >= midCutoff && $0.date <= now }
        let olderEntries = entries.filter { $0.date >= startCutoff && $0.date < midCutoff }

        let recentRate = recentEntries.isEmpty ? 0 : Double(recentEntries.filter(\.completed).count) / Double(recentEntries.count)
        let olderRate = olderEntries.isEmpty ? 0 : Double(olderEntries.filter(\.completed).count) / Double(olderEntries.count)

        return recentRate - olderRate
    }

    // MARK: - Next Dose

    var nextDose: ProtocolEntry? {
        bumpVersionIfDayChanged()
        if let cached = _nextDose, cached.version == cacheVersion { return cached.value }
        let now = Date()
        let today = todayEntries
        let result = today.first { !$0.completed && $0.date > now }
            ?? today.first { !$0.completed }
        _nextDose = (cacheVersion, result)
        return result
    }

    // MARK: - Stack-derived caches
    //
    // HomeView reads `stackPeptides` / `stackWarnings` / `stackRecommendations`
    // / `stackCompleteness` / `cycleTransitions` on every render. Each of
    // those engines scans the full peptide database and / or the protocol
    // list — combined ~60–80ms with a populated stack. Caching them keyed
    // by `cacheVersion` makes the second-and-onward render free.

    /// Distinct peptides across all active protocols, dedup-stable on first
    /// appearance.
    var stackPeptides: [Peptide] {
        if let cached = _stackPeptides, cached.version == cacheVersion { return cached.value }
        var seen = Set<UUID>()
        let result = activeProtocols.flatMap(\.peptides).filter { seen.insert($0.id).inserted }
        _stackPeptides = (cacheVersion, result)
        return result
    }

    var stackWarnings: [StackRecommendationEngine.Warning] {
        if let cached = _stackWarnings, cached.version == cacheVersion { return cached.value }
        let result = StackRecommendationEngine.warnings(
            for: stackPeptides,
            activeProtocols: activeProtocols
        )
        _stackWarnings = (cacheVersion, result)
        return result
    }

    var stackRecommendations: [StackRecommendationEngine.Recommendation] {
        if let cached = _stackRecommendations, cached.version == cacheVersion { return cached.value }
        let context = StackRecommendationEngine.RecommendationContext(
            currentPeptides: stackPeptides,
            database: peptideDatabase,
            goals: profile.goals,
            activeProtocols: activeProtocols,
            entries: entries
        )
        let result = StackRecommendationEngine.recommendations(context: context)
        _stackRecommendations = (cacheVersion, result)
        return result
    }

    /// Smart Planner nudges, cached like the other engines so the
    /// Protocols tab doesn't re-filter every entry on each render.
    var smartCycleSuggestions: [SmartCyclePlanner.Suggestion] {
        if let cached = _smartCycleSuggestions, cached.version == cacheVersion { return cached.value }
        let result = SmartCyclePlanner.suggestions(protocols: protocols, entries: entries)
        _smartCycleSuggestions = (cacheVersion, result)
        return result
    }

    var stackCompleteness: StackRecommendationEngine.StackCompleteness? {
        if let cached = _stackCompleteness, cached.version == cacheVersion { return cached.value }
        let result = StackRecommendationEngine.stackCompleteness(
            for: stackPeptides,
            goals: profile.goals,
            from: peptideDatabase
        )
        _stackCompleteness = (cacheVersion, result)
        return result
    }

    var cycleTransitions: [StackRecommendationEngine.CycleTransition] {
        if let cached = _cycleTransitions, cached.version == cacheVersion { return cached.value }
        let result = StackRecommendationEngine.cycleTransitions(for: activeProtocols)
        _cycleTransitions = (cacheVersion, result)
        return result
    }

    /// Top insight (the one HomeView surfaces). InsightEngine sorts by
    /// priority; we just take the first because the Home tab only renders
    /// one insight.
    var topInsight: InsightEngine.Insight? {
        if let cached = _topInsight, cached.version == cacheVersion { return cached.value }
        let result = InsightEngine.generateInsights(
            from: entries,
            protocols: protocols,
            frozenDayKeys: profile.streakFreezeDays
        ).first
        _topInsight = (cacheVersion, result)
        return result
    }

    // MARK: - Profile

    func updateGoals(_ goals: Set<String>) {
        profile.goals = Array(goals).sorted()
        // A pinned goal that's no longer in the active goal set is meaningless
        // — drop it so the home tab doesn't surface a stale recommendation.
        if let pinned = profile.primaryGoal, !goals.contains(pinned) {
            profile.primaryGoal = nil
        }
        // stackRecommendations / stackCompleteness depend on profile.goals,
        // so bump the cache version explicitly — the protocols/entries didSet
        // bumpers don't fire on a profile-only change.
        cacheVersion &+= 1
        save()
    }

    /// Pin or clear the headline goal. Pass `nil` to remove the pin. The goal
    /// must already exist in `profile.goals` — otherwise the call is ignored
    /// and a warning is logged so a future silent-drop is visible to anyone
    /// scraping Console for the onboarding category.
    func setPrimaryGoal(_ goal: String?) {
        if let goal, !profile.goals.contains(goal) {
            AppLog.onboarding.warning(
                "setPrimaryGoal('\(goal, privacy: .public)') dropped — not in profile.goals. Call updateGoals first."
            )
            return
        }
        profile.primaryGoal = goal
        // Same reason as updateGoals: goal-derived caches are stale until the
        // next protocols/entries mutation without this manual bump.
        cacheVersion &+= 1
        save()
    }

    func updateBodyMetrics(_ metrics: BodyMetrics) {
        profile.bodyMetrics = metrics
        save()
    }

    /// Updates the calorie + macro targets surfaced on the Meals tab.
    /// Pass `nil` to clear them and re-show the empty-state CTA.
    func updateNutritionTargets(_ targets: NutritionTargets?) {
        profile.nutritionTargets = targets
        save()
    }

    /// Expenditure estimate from logged intake + weight trend, or the
    /// formula when there isn't enough data yet. Nil only when there's
    /// neither logging history nor complete body stats.
    func expenditureEstimate(asOf now: Date = Date()) -> AdaptiveTDEEEngine.Estimate? {
        AdaptiveTDEEEngine.estimate(
            weights: dedupedWeightHistory,
            intake: Array(profile.dailyConsumption.values),
            formulaTDEE: NutritionMath.formulaTDEE(for: profile.bodyMetrics),
            asOf: now
        )
    }

    /// Moves the saved targets with the adaptive estimate, MacroFactor-style,
    /// but only while they're still the recommendation the user accepted —
    /// hand-entered numbers are never overwritten.
    func refreshAdaptiveTargets(asOf now: Date = Date()) {
        guard
            AdaptiveTDEESettings.isEnabled,
            let current = profile.nutritionTargets,
            let estimate = expenditureEstimate(asOf: now),
            estimate.source == .adaptive,
            let next = NutritionMath.recommendedTargets(
                for: profile.bodyMetrics,
                goalRaw: profile.primaryGoal,
                maintenanceKcal: Double(estimate.kcal)
            ),
            AdaptiveTDEEEngine.shouldFollow(
                current: current,
                followed: AdaptiveTDEESettings.followedTargets,
                next: next
            )
        else { return }
        AdaptiveTDEESettings.followedTargets = next
        updateNutritionTargets(next)
    }

    // MARK: - Lifestyle data
    //
    // Bodyweight, nutrition, water, workouts, and the progress-photo
    // manifest. The mutating business logic lives in
    // `LifestyleDataLogic` so it's unit-testable in isolation; the
    // methods here are thin coordinators that delegate, then `save()`.
    // Read-only accessors (`dedupedWeightHistory`, `consumption(for:)`,
    // `workoutSummary(for:)`) follow the same pattern so every site has
    // one place to find the rule.

    /// Appends a bodyweight entry; dedups to one entry per calendar day.
    func logWeight(kg: Double, date: Date = Date()) {
        LifestyleDataLogic.logWeight(into: &profile, kg: kg, date: date)
        save()
        guard HealthSyncSettings.isEnabled else { return }
        enqueueBodyMassHealthWrite { await HealthKitService.shared.writeBodyMass(kg: kg, date: date) }
    }

    /// Body-mass mirroring is delete-then-save for the day, so two quick
    /// weigh-ins run concurrently would both delete, then both save and
    /// leave two samples. Each write waits for the one before it.
    @ObservationIgnored private var bodyMassHealthWriteTask: Task<Void, Never>?

    private func enqueueBodyMassHealthWrite(_ write: @escaping @Sendable @MainActor () async -> Void) {
        let previous = bodyMassHealthWriteTask
        bodyMassHealthWriteTask = Task {
            await previous?.value
            await write()
        }
    }

    /// Weight history with at-most-one entry per calendar day.
    /// See `LifestyleDataLogic.dedupedWeightHistory` for the dedup rule
    /// (most recently logged entry within each day wins).
    var dedupedWeightHistory: [WeightEntry] {
        LifestyleDataLogic.dedupedWeightHistory(profile)
    }

    func deleteWeight(id: UUID) {
        let deleted = profile.weightHistory.first { $0.id == id }
        let wasRecordedImport = repo.isHealthWeightImport(id)
        repo.dismissHealthWeight(id: id)
        LifestyleDataLogic.deleteWeight(from: &profile, id: id)
        save()
        guard let deleted, HealthSyncSettings.isEnabled else { return }
        let day = deleted.date
        if !wasRecordedImport {
            Task { await self.dismissLegacyImports(of: deleted) }
        }
        enqueueBodyMassHealthWrite { await HealthKitService.shared.deleteBodyMass(onDayOf: day) }
    }

    /// Earlier builds imported Health weigh-ins under random ids, so
    /// deleting one can't dismiss its sample by id; dismissing the
    /// matching outside sample keeps the next pass from re-importing it.
    private func dismissLegacyImports(of deleted: WeightEntry) async {
        let external = await HealthKitService.shared.externalWeights(days: HealthSyncEngine.importWindowDays)
        let imports = HealthSyncEngine.legacyImports(of: deleted, in: external)
        repo.dismissHealthWeights(ids: Set(imports.map(\.id)))
    }

    /// Exact-amount water log behind every entry point (quick-adds,
    /// Siri, the Watch, the widget). A negative amount is the Undo
    /// path; the day clamps at zero.
    func logWater(fluidOunces: Double, date: Date = Date()) {
        LifestyleDataLogic.logWater(into: &profile, fluidOunces: fluidOunces, date: date)
        save()
        mirrorWaterToHealth(fluidOunces: fluidOunces, date: date)
    }

    private func mirrorWaterToHealth(fluidOunces: Double, date: Date) {
        guard HealthSyncSettings.isEnabled else { return }
        Task {
            if fluidOunces > 0 {
                await HealthKitService.shared.writeWater(fluidOunces: fluidOunces, date: date)
            } else {
                await HealthKitService.shared.deleteLatestWater(fluidOunces: -fluidOunces, onDayOf: date)
            }
        }
    }

    /// Today's (or any day's) consumption bucket, or an empty stub.
    func consumption(for date: Date = Date()) -> DailyConsumption {
        LifestyleDataLogic.consumption(in: profile, for: date)
    }

    // MARK: - Meal entries

    /// Logs a fully-formed `MealEntry` (with category + source) and
    /// keeps the per-day aggregate in lockstep. Prefer over the
    /// legacy `logMeal(...)` for new code — gives you per-meal
    /// undo, category breakdowns, and a stable identifier you can
    /// hold onto for HealthKit sample mapping.
    ///
    /// When the meal Health toggle is on, fires a background
    /// HealthKit write tagged with the entry's UUID. The HK write is
    /// fire-and-forget — failures log and disappear because they
    /// shouldn't block the in-app log. Undo removes the matching
    /// samples by metadata anchor.
    func logMealEntry(_ entry: MealEntry) {
        LifestyleDataLogic.logMealEntry(into: &profile, entry: entry)
        save()
        if HealthSyncSettings.isNutritionEnabled {
            Task { await HealthKitService.shared.writeMealEntry(entry) }
        }
    }

    /// Re-logs the previous day's `category` entries at the current time —
    /// the meal reminder's "Same as yesterday" action. A no-op when that
    /// meal is already logged today, so a second tap can't double it.
    func repeatMeals(_ category: MealCategory, from reminderDate: Date) {
        let now = Date()
        let calendar = Calendar.current
        guard !profile.mealHistory.contains(where: {
            $0.category == category && calendar.isDate($0.date, inSameDayAs: now)
        }) else { return }

        let previous = DailyReminderEngine.previousDayMeals(category, before: reminderDate, in: profile.mealHistory)
        for meal in previous {
            logMealEntry(MealEntry(
                date: now,
                category: category,
                name: meal.name,
                calories: meal.calories,
                proteinG: meal.proteinG,
                carbsG: meal.carbsG,
                fatG: meal.fatG,
                sourceID: meal.sourceID,
                source: meal.source,
                components: meal.components
            ))
        }
    }

    /// Stable IDs make retry and interrupted completion idempotent.
    /// Health writes start only after the local profile commit succeeds.
    @ObservationIgnored private var mealHealthWriteTask: Task<Void, Never>?

    func commitScannedMeals(_ meals: [MealEntry], undo: Bool = false) throws {
        var candidate = profile
        var changed: [MealEntry] = []
        for meal in meals {
            if undo {
                guard candidate.mealHistory.contains(where: { $0.id == meal.id }) else { continue }
                LifestyleDataLogic.unlogMealEntry(from: &candidate, id: meal.id)
            } else {
                guard !candidate.mealHistory.contains(where: { $0.id == meal.id }) else { continue }
                LifestyleDataLogic.logMealEntry(into: &candidate, entry: meal)
            }
            changed.append(meal)
        }
        if !isEphemeral {
            try repo.saveMealProfileDurably(candidate, since: persistedProfile)
            persistedProfile = candidate
        }
        profile = candidate
        // Keep the established projection/achievement save path. It may save
        // other pending changes; the meals above already have durable storage.
        save()
        if HealthSyncSettings.isNutritionEnabled && !isEphemeral {
            let previous = mealHealthWriteTask
            mealHealthWriteTask = Task {
                await previous?.value
                for meal in changed {
                    if undo { await HealthKitService.shared.deleteSamples(forEntryID: meal.id) }
                    else { await HealthKitService.shared.writeMealEntry(meal) }
                }
            }
        }
    }

    /// Updates a previously logged meal entry — category, macros, or
    /// date — keeping the per-day aggregate in lockstep. The previous
    /// implementation replaced the array element only, so editing
    /// calories 500 → 800 left the macro ring 300 kcal low, and moving
    /// an entry's date left both days' totals wrong (the invariant
    /// `LifestyleDataLogic.logMealEntry` documents). Now routed through
    /// `applyMealEntryEdit`, which reverses the old contribution and
    /// applies the new one. The Apple Health mirror is refreshed the
    /// same way the delete path already does: old samples removed by
    /// external UUID, new values written. No-op when the id isn't in
    /// history.
    func updateMealEntry(_ updated: MealEntry) {
        guard profile.mealHistory.contains(where: { $0.id == updated.id }) else { return }
        LifestyleDataLogic.applyMealEntryEdit(into: &profile, updated: updated)
        save()
        if HealthSyncSettings.isNutritionEnabled {
            Task {
                await HealthKitService.shared.deleteSamples(forEntryID: updated.id)
                await HealthKitService.shared.writeMealEntry(updated)
            }
        }
    }

    /// Removes a meal entry by id and rolls back its contribution to
    /// the day's aggregate. Used by every review screen's Undo button
    /// once it switches to the new logging path.
    func unlogMealEntry(id: UUID) {
        LifestyleDataLogic.unlogMealEntry(from: &profile, id: id)
        save()
        TableMomentStore.shared.removeDish(id: id)
        if HealthSyncSettings.isNutritionEnabled {
            Task { await HealthKitService.shared.deleteSamples(forEntryID: id) }
        }
    }

    /// Flips the Apple Health write toggle. When turning ON, requests
    /// HK write permission first — if that fails (sim, every type
    /// denied, no HealthKit on iPad), the toggle stays off and we
    /// surface the failure via the returned Bool so the caller can
    /// point the user to Settings. A later revocation in Settings is
    /// picked up on the next foreground (`turnOffDeniedHealthWrites`).
    @discardableResult
    func setHealthKitNutritionEnabled(_ enabled: Bool) async -> Bool {
        if enabled {
            let granted = await HealthKitService.shared.requestNutritionWriteAuthorization()
            guard granted else {
                UserDefaults.standard.set(false, forKey: HealthSyncSettings.nutritionEnabledKey)
                return false
            }
        }
        UserDefaults.standard.set(enabled, forKey: HealthSyncSettings.nutritionEnabledKey)
        return true
    }

    /// Turns "Sync workouts, weight and water" on or off. Like the meal
    /// toggle, it only stays on while some write type is allowed.
    @discardableResult
    func setHealthActivitySyncEnabled(_ enabled: Bool) async -> Bool {
        if enabled {
            guard await HealthKitService.shared.requestActivitySyncAuthorization() else {
                UserDefaults.standard.set(false, forKey: HealthSyncSettings.enabledKey)
                return false
            }
        }
        UserDefaults.standard.set(enabled, forKey: HealthSyncSettings.enabledKey)
        if enabled { await importHealthWeights() }
        return true
    }

    /// Takes in weigh-ins from a smart scale or another app for days
    /// Atlas has no weight, so the trend and checklist see them too.
    /// They're kept on this device only — never synced to iCloud.
    func importHealthWeights() async {
        guard HealthSyncSettings.isEnabled else { return }
        let external = await HealthKitService.shared.externalWeights(days: HealthSyncEngine.importWindowDays)
        let additions = HealthSyncEngine.weightsToImport(
            external,
            existing: profile.weightHistory,
            dismissed: repo.dismissedHealthWeightIDs
        )
        guard !additions.isEmpty, repo.recordHealthWeightImports(additions) else { return }
        profile.weightHistory = (profile.weightHistory + additions).sorted { $0.date < $1.date }
        save()
    }

    /// Per-category breakdown for today (or any day). Used by the
    /// `MealCategoriesCard` on the Meals tab.
    func mealsByCategory(for date: Date = Date()) -> LifestyleDataLogic.CategoryBreakdown {
        LifestyleDataLogic.mealsByCategory(in: profile, for: date)
    }

    /// Individual meal entries logged on a specific day, newest first.
    /// Populates the meal-history list views.
    func mealEntries(for date: Date = Date()) -> [MealEntry] {
        LifestyleDataLogic.mealEntries(in: profile, for: date)
    }

    /// Active meal-logging streak in calendar days. Today is treated
    /// as a grace day — the streak doesn't reset just because the
    /// user hasn't logged yet this morning.
    var mealLoggingStreak: Int {
        mealStreaks.current
    }

    /// All-time best meal-logging streak. Surfaced on the Lifestyle
    /// tab when the user is below their personal record.
    var bestMealLoggingStreak: Int {
        mealStreaks.best
    }

    private struct MealStreakCache {
        let history: [MealEntry]
        let freezeDays: Set<String>
        let day: Date
        let current: Int
        let best: Int
    }

    @ObservationIgnored private var mealStreakCache: MealStreakCache?

    /// Both streaks walk the whole meal history, and the Meals screen
    /// re-reads them on every profile change — each water tap included.
    /// Reused until the history, the freezes or the day change; an
    /// untouched array compares equal by identity, so the check is cheap.
    private var mealStreaks: (current: Int, best: Int) {
        let day = Calendar.current.startOfDay(for: Date())
        if let cached = mealStreakCache, cached.day == day,
           cached.history == profile.mealHistory, cached.freezeDays == profile.streakFreezeDays {
            return (cached.current, cached.best)
        }
        let current = LifestyleDataLogic.mealLoggingStreak(in: profile)
        let best = LifestyleDataLogic.bestMealLoggingStreak(in: profile)
        mealStreakCache = MealStreakCache(history: profile.mealHistory, freezeDays: profile.streakFreezeDays,
                                          day: day, current: current, best: best)
        return (current, best)
    }

    // MARK: - Outcome check-ins

    /// Logs (or replaces) a daily wellness check-in. One per day.
    func logOutcome(_ entry: OutcomeEntry) {
        LifestyleDataLogic.logOutcome(into: &profile, entry: entry)
        save()
    }

    /// Today's check-in if the user has filled one in already, else
    /// nil — drives the prompt-vs-summary state of the daily card.
    func outcome(for date: Date = Date()) -> OutcomeEntry? {
        LifestyleDataLogic.outcome(in: profile, for: date)
    }

    /// Last `days` days of check-ins, oldest first. Feeds the
    /// sparkline and the correlation engine.
    func recentOutcomes(days: Int = 30) -> [OutcomeEntry] {
        LifestyleDataLogic.recentOutcomes(in: profile, days: days)
    }

    // MARK: - Lab values

    /// Saves a new lab entry or replaces an existing one matched
    /// by id. The list keeps a newest-first sort order so list
    /// views read without an extra sort pass.
    func saveLabValue(_ value: LabValue) {
        LabDataLogic.saveLabValue(into: &profile, value: value)
        save()
    }

    /// Removes a lab entry by id. Idempotent — calling twice on
    /// the same id is a no-op the second time.
    func deleteLabValue(id: UUID) {
        if let orphanedReport = LabDataLogic.deleteLabValue(from: &profile, id: id) {
            LabReportStorage.delete(orphanedReport)
        }
        save()
    }

    /// All entries for one panel, oldest-first. Used by the per-
    /// panel chart view.
    func labEntries(for panel: LabPanel) -> [LabValue] {
        LabDataLogic.entries(in: profile, for: panel)
    }

    /// Most-recent value + trend direction for every panel the
    /// user has logged. Drives the headline grid on the labs view.
    var latestLabSummaries: [LabDataLogic.LatestSummary] {
        LabDataLogic.latestPerPanel(in: profile)
    }

    // MARK: - Travel mode

    /// Shifts every non-completed protocol's preferred dose times by the
    /// timezone delta. Use when the user opts to translate their
    /// schedule to local clock after a flight. Also acknowledges
    /// the new timezone so the prompt won't re-fire on the next
    /// launch in the same zone. Regenerates today's entries (keeping
    /// any already logged) so the new times reflect immediately on the
    /// Home + Lifestyle tabs, then moves the pending reminders and Live
    /// Activities to them.
    func applyTravelShift(toTimezone identifier: String, minutesDelta: Int) {
        TravelModeLogic.shiftProtocolTimes(in: &protocols, byMinutes: minutesDelta)
        TravelModeLogic.acknowledgeTimezoneChange(in: &profile, to: identifier)
        for proto in activeProtocols {
            regenerateTodayEntriesPreservingLogs(for: proto)
        }
        save()
        rescheduleNotificationsIfEnabled()
        reconcileDoseLiveActivities()
    }

    /// User declined the schedule shift but acknowledged the
    /// detection. Records the new identifier so we don't keep
    /// re-prompting at every launch.
    func acknowledgeTimezone(_ identifier: String) {
        TravelModeLogic.acknowledgeTimezoneChange(in: &profile, to: identifier)
        save()
    }

    // MARK: - Streak freeze

    /// True when the user has a freeze available this calendar
    /// month. Drives the at-risk prompt's "Use freeze" button.
    var streakFreezeAvailable: Bool {
        StreakFreezeService.hasFreezeAvailable(in: profile)
    }

    /// Spends one freeze on the given calendar day (defaults to
    /// yesterday — the day the user is trying to shield). Returns
    /// true on success; false when no freeze is available or the
    /// day is already covered.
    @discardableResult
    func applyStreakFreeze(for date: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()) -> Bool {
        let applied = StreakFreezeService.applyFreeze(in: &profile, for: date)
        if applied {
            // currentStreak / bestStreak now consult the freeze set —
            // bump the cache version so they recompute (profile
            // mutations don't auto-bump it the way protocols/entries do).
            cacheVersion &+= 1
            save()
        }
        return applied
    }

    /// True when a freeze is available AND a meaningful habit streak would be
    /// lost because yesterday (a due day) was missed and isn't already
    /// frozen — so spending a freeze on yesterday would save it. Drives the
    /// Habits tab's "Streak at risk" prompt. The per-habit walk runs only
    /// when a freeze is actually available (at most once a month), so it
    /// stays off the common render path.
    var habitStreakAtRisk: Bool {
        guard streakFreezeAvailable else { return false }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let dayBefore = calendar.date(byAdding: .day, value: -2, to: today)
        else { return false }
        if StreakFreezeService.isFrozen(yesterday, in: profile) { return false }

        let entries = profile.habitEntries
        let frozen = profile.streakFreezeDays
        return activeHabits.contains { habit in
            guard habit.schedule.isDue(on: yesterday, calendar: calendar) else { return false }
            let target = habit.targetValue ?? 1
            let doneYesterday = entries.contains {
                $0.habitId == habit.id
                    && calendar.isDate($0.date, inSameDayAs: yesterday)
                    && $0.value >= target
            }
            if doneYesterday { return false }
            // Only prompt when there was a real streak (≥2) running into the
            // gap, computed as of the day before yesterday.
            let priorStreak = HabitsService.summary(
                for: habit, entries: entries, frozenDayKeys: frozen, on: dayBefore
            ).currentStreak
            return priorStreak >= 2
        }
    }

    // MARK: - Recipes

    /// Saves a new recipe or replaces an existing one (matched by
    /// id). Bumps `updatedAt` so the list re-sorts to put the
    /// just-edited recipe on top.
    func saveRecipe(_ recipe: Recipe) {
        RecipeDataLogic.saveRecipe(into: &profile, recipe: recipe)
        save()
    }

    /// Removes one recipe by id. Idempotent.
    func deleteRecipe(id: UUID) {
        RecipeDataLogic.deleteRecipe(from: &profile, id: id)
        save()
    }

    // MARK: - Protocol notes

    /// Saves a new protocol note or replaces an existing one
    /// matched by id. Bumps `updatedAt` so the timeline re-sorts
    /// to put the just-edited entry on top within its day bucket.
    func saveProtocolNote(_ note: ProtocolNote) {
        var updated = note
        updated.updatedAt = Date()
        if let index = profile.protocolNotes.firstIndex(where: { $0.id == note.id }) {
            profile.protocolNotes[index] = updated
        } else {
            profile.protocolNotes.append(updated)
        }
        save()
    }

    /// Removes one note by id. Idempotent.
    func deleteProtocolNote(id: UUID) {
        profile.protocolNotes.removeAll { $0.id == id }
        save()
    }

    /// All notes for one protocol, newest-first. Powers the
    /// per-protocol timeline view.
    func protocolNotes(for protocolID: UUID) -> [ProtocolNote] {
        profile.protocolNotes
            .filter { $0.protocolID == protocolID }
            .sorted { $0.date > $1.date }
    }

    /// Logs a recipe as a single `MealEntry` summing every
    /// component's macros. The entry's `name` is the recipe name
    /// so the meal-history list reads "Morning bowl" rather than
    /// the comma-joined ingredient list. Source tagged as
    /// `.custom` since recipes are user-defined compositions.
    @discardableResult
    func logRecipe(_ recipe: Recipe, category: MealCategory? = nil, at date: Date = Date()) -> MealEntry? {
        guard let totals = RecipeDataLogic.review(
            for: recipe,
            customFoods: profile.customFoods
        ).totals else { return nil }
        let chosenCategory = category ?? MealCategory.auto(for: date)
        let entry = MealEntry(
            loggable: totals,
            name: recipe.name,
            category: chosenCategory,
            source: .custom,
            sourceID: nil,
            date: date
        )
        do {
            try commitScannedMeals([entry])
            return entry
        } catch {
            lastError = Self.saveFailureMessage
            return nil
        }
    }

    // MARK: - Food library

    /// Adds (or replaces) a user-defined food in the library. Replace
    /// matches on `id` so editing an existing food round-trips through
    /// the same call. After saving, fires a background reindex so the
    /// new food is searchable from device Spotlight on the next pull-
    /// down.
    func saveCustomFood(_ food: CustomFood) {
        var updated = food
        updated.updatedAt = Date()
        if let index = profile.customFoods.firstIndex(where: { $0.id == food.id }) {
            profile.customFoods[index] = updated
        } else {
            profile.customFoods.insert(updated, at: 0)
        }
        save()
        reindexFoodLibraryInBackground()
    }

    /// Fills in packshots found in the background. Leaves `updatedAt`
    /// alone: it orders My Foods, and a found picture is not an edit.
    func attachPictures(_ pictures: [UUID: URL]) {
        guard !pictures.isEmpty else { return }
        var foods = profile.customFoods
        for index in foods.indices where foods[index].imageURL == nil {
            foods[index].imageURL = pictures[foods[index].id]
        }
        profile.customFoods = foods
        save()
    }

    /// Removes a custom food and its favorite-set membership in one
    /// pass so the favorites tab can't keep a dangling reference.
    /// Reindexes Spotlight via the same full-rewrite path that
    /// `saveCustomFood` and `toggleFavoriteFood` use — the targeted
    /// `removeCustomFood(id:)` shortcut would race with a concurrent
    /// `saveCustomFood` reindex that captured a pre-delete profile
    /// snapshot, re-introducing the just-deleted item to the index.
    /// Full reindex is idempotent and authoritative.
    func deleteCustomFood(id: UUID) {
        profile.customFoods.removeAll { $0.id == id }
        profile.favoriteFoodIDs.remove("custom:\(id.uuidString)")
        save()
        reindexFoodLibraryInBackground()
    }

    /// Flips the favorite flag for a food ID (OFF barcode or
    /// `custom:<uuid>`). Idempotent — calling twice returns to the
    /// original state. Reindexes Spotlight on the change so favorites
    /// surface (or stop surfacing) in the device search.
    func toggleFavoriteFood(id: String) {
        if profile.favoriteFoodIDs.contains(id) {
            profile.favoriteFoodIDs.remove(id)
        } else {
            profile.favoriteFoodIDs.insert(id)
        }
        save()
        reindexFoodLibraryInBackground()
    }

    /// Fire-and-forget Spotlight reindex. Pulls cached OFF favorites
    /// off `BarcodeProductCache` so they index with their full name
    /// + brand. Failures log but don't propagate — Spotlight is a
    /// nice-to-have surface, never a critical-path dependency.
    ///
    /// Cancels any in-flight reindex Task before scheduling a new
    /// one. Without this, two rapid mutations (save + favorite
    /// toggle in quick succession) would race: whichever Task
    /// finished last would overwrite Spotlight with its captured
    /// profile snapshot, regardless of which mutation actually
    /// landed in the persisted profile first.
    private func reindexFoodLibraryInBackground() {
        reindexTask?.cancel()
        let snapshot = profile
        let offIDs = profile.favoriteFoodIDs.filter { !$0.hasPrefix("custom:") }
        reindexTask = Task {
            var cached: [ScannedProduct] = []
            cached.reserveCapacity(offIDs.count)
            for id in offIDs {
                if Task.isCancelled { return }
                if let product = await BarcodeProductCache.shared.read(barcode: id) {
                    cached.append(product)
                }
            }
            guard !Task.isCancelled else { return }
            await FoodSpotlightService.shared.reindex(
                profile: snapshot,
                cachedFavorites: cached
            )
        }
    }

    /// Public entry point for the app-launch hydration in `PeptideApp`.
    /// Kicks the same fire-and-forget reindex pipeline so a fresh
    /// install or a CloudKit pull on a new device populates Spotlight
    /// without forcing the user to edit any food.
    func reindexFoodSpotlight() {
        reindexFoodLibraryInBackground()
    }

    func isFavoriteFood(id: String) -> Bool {
        profile.favoriteFoodIDs.contains(id)
    }

    /// Quick-log workout entry — kept for the freeform "Movement"
    /// surface on the Today scroll. Plan C reconciled the dual store
    /// split: this method no longer writes to the legacy
    /// `profile.workoutHistory` array; instead it constructs a
    /// `WorkoutSession` (empty exercises, the legacy sets×reps in the
    /// `note` field) and persists through the same SwiftData repo
    /// the Train tab reads from. Both surfaces converge on
    /// `StoredWorkoutSession` so a quick-log entry shows up in Train,
    /// and a Train-tab session shows up in the Today summary.
    func logWorkout(_ entry: WorkoutEntry) {
        let finishedAt = entry.date.addingTimeInterval(
            TimeInterval(max(0, entry.durationMinutes) * 60)
        )
        let session = WorkoutSession(
            id: entry.id,
            name: entry.name,
            routineID: nil,
            programID: nil,
            startedAt: entry.date,
            finishedAt: finishedAt,
            exercises: [],
            note: String(localized: "Quick-log · \(entry.sets) sets × \(entry.reps) reps"),
            perceivedEffort: nil,
            focus: WorkoutFocusState(timing: entry.durationMinutes > 0 ? .tracked : .notTracked)
        )
        repo.beginSaveBatch()
        repo.upsertWorkoutSession(session)
        // Invalidate caches and refresh the widget/Watch surfaces.
        // `bumpVersionIfDayChanged()` was a no-op on the common
        // same-day path, so the Today widget's workout count went
        // stale until an unrelated mutation happened to bump it.
        cacheVersion &+= 1
        if repo.commitDidFail {
            lastError = Self.saveFailureMessage
        } else {
            if HealthSyncSettings.isEnabled {
                Task { await HealthKitService.shared.writeWorkout(session) }
            }
            refreshTrainingGlanceables()
        }
        // Quick-log sessions have no exercises, so no PRs are possible.
        recordWorkoutFinished(detectedPRCount: 0)
    }

    /// Deletes a workout by ID from the structured store. Same plumbing
    /// as `WorkoutSessionService.discardWorkout` for the active path —
    /// here it targets the historical row directly.
    func deleteWorkout(id: UUID) {
        // Capture which exercises the session touched before the row is
        // gone — its PRs are derived data and must be recomputed from
        // the surviving history, or a deleted workout's record would
        // stand forever with no path to ever correct it.
        let affectedExercises = repo.loadWorkoutSession(id: id)
            .map { Set($0.exercises.map(\.exerciseID)) } ?? []
        repo.beginSaveBatch()
        repo.deleteWorkoutSession(id: id)
        // Not gated on the sync toggle: a workout mirrored while sync was
        // on must still leave Health. It matches only Atlas's own sample
        // and fails quietly without permission.
        Task { await HealthKitService.shared.deleteWorkout(id: id) }
        PRDetectionEngine.shared.recompute(exerciseIDs: affectedExercises)
        WorkoutSessionService.shared.invalidatePreviousSetCache()
        cacheVersion &+= 1
        // Same reason as `recordWorkoutFinished`: a repo-level write is
        // invisible to the property observers, so derived snapshots need
        // telling explicitly or a deleted workout lingers on Today.
        revision &+= 1
        if repo.commitDidFail {
            lastError = Self.saveFailureMessage
        } else {
            refreshTrainingGlanceables()
        }
    }

    /// Fired when a workout is finalized (structured finish via
    /// `WorkoutSessionService.finishWorkout`, or quick-log via
    /// `logWorkout`). Checks training achievements off a cheap session
    /// count + the PR signal — runs only on this workout event, never on
    /// the generic save hot-path.
    func recordWorkoutFinished(detectedPRCount: Int) {
        // A structured finish writes StoredWorkoutSession through the repo,
        // not through `protocols` / `entries` / `profile`, so none of the
        // `didSet` bumps fire. Views that recompute a derived snapshot off
        // `.task(id: revision)` — Today's timeline among them — would keep
        // serving the pre-workout view for as long as they stayed mounted,
        // until some unrelated mutation happened to bump it. Bumped before
        // the ephemeral guard: screenshot mode still has to redraw.
        cacheVersion &+= 1
        revision &+= 1
        guard !isEphemeral, !AchievementService.shared.needsSilentSeed else { return }
        AchievementService.shared.checkTrainingAchievements(
            workoutCount: repo.workoutSessionCount(),
            prDetected: detectedPRCount > 0
        )
    }

    /// Rewrites the glanceable payload after a training-lifecycle event.
    ///
    /// Start / finish / discard all write `StoredWorkoutSession` through
    /// the repo rather than through `protocols` / `entries` / `profile`,
    /// so none of the `didSet` bumps fire and nothing else calls
    /// `updateWidgetData`. Without this the training widget keeps
    /// describing the previous workout until some unrelated mutation
    /// happens along — showing a running timer for a workout that was
    /// discarded, or yesterday's session right after the user finished
    /// today's. Same reasoning as the cache bump in
    /// `recordWorkoutFinished`, applied to the out-of-process snapshot.
    func refreshTrainingGlanceables() {
        widgetWorkouts = nil
        updateWidgetData()
        updateWatchData()
    }

    /// Sends the active workout alone to the Watch. Runs on every set
    /// edit, so it skips the full snapshot's habit and score math.
    func pushWorkoutToWatch() {
        WatchSyncService.shared.updateWorkout(watchWorkout)
    }

    private var watchWorkout: WatchWorkoutSnapshot? {
        WatchWorkoutSnapshotBuilder.snapshot(
            of: WorkoutSessionService.shared.activeSession,
            defaultRestSeconds: profile.trainingPreferences?.restTimerDefault ?? 90
        )
    }



    /// Editing changes derived records and totals, but earns no second reward.
    func workoutWasEdited(exerciseIDs: Set<String>) {
        PRDetectionEngine.shared.recompute(exerciseIDs: exerciseIDs)
        WorkoutSessionService.shared.invalidatePreviousSetCache()
        cacheVersion &+= 1
        revision &+= 1
        refreshTrainingGlanceables()
    }

    /// Start dates of workout sessions from the last `days` days. The
    /// weekly recap counts training days as activity.
    func recentWorkoutDates(days: Int = 7) -> [Date] {
        let now = Date()
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: now)) else { return [] }
        return repo.loadWorkoutSessions(startedBetween: start..<now).map(\.startedAt)
    }

    /// (count, totalMinutes) for finished workout sessions on `date`'s
    /// calendar day. A session still in progress isn't logged yet.
    func workoutSummary(for date: Date = Date()) -> (count: Int, minutes: Int) {
        // Reads from `StoredWorkoutSession` now (Plan C) — quick-log
        // entries and Train-tab sessions both land there. Uses the
        // windowed repo fetch so this method doesn't fault the whole
        // session table on every Today-tab render — a long-term user
        // could have years of sessions, and this is called from a
        // SwiftUI body.
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else {
            return (0, 0)
        }
        let sessions = repo.loadWorkoutSessions(startedBetween: dayStart..<dayEnd)
            .filter { !$0.isActive }
        let minutes = sessions.reduce(0) { $0 + $1.elapsedSeconds() / 60 }
        return (sessions.count, minutes)
    }

    func addProgressPhotoFilename(_ filename: String) {
        LifestyleDataLogic.addProgressPhotoFilename(to: &profile, filename)
        save()
    }

    func removeProgressPhotoFilename(_ filename: String) {
        LifestyleDataLogic.removeProgressPhotoFilename(from: &profile, filename)
        save()
    }

    /// Toggle off (revoke local link) is unconditional. Toggle ON
    /// succeeds once Health's permission sheet completes. HealthKit
    /// never reveals denied read access, so a user who allowed nothing
    /// still connects; `HealthKitService.hasReadableData` is how the
    /// Profile card tells them nothing is visible. Returns false when
    /// the request itself failed (no HealthKit, or it threw).
    @discardableResult
    func toggleHealthConnection() async -> Bool {
        if profile.healthConnected {
            HealthSyncSettings.setConnected(false)
            profile.healthConnected = false
            save()
            await refreshWatchVitals()
            return true
        }
        let granted = await HealthKitService.shared.requestAuthorization()
        guard granted else {
            AppLog.healthKit.warning("toggleHealthConnection blocked — no HealthKit grant")
            return false
        }
        HealthSyncSettings.setConnected(true)
        profile.healthConnected = true
        save()
        await refreshWatchVitals()
        return true
    }

    /// Health permission is granted per device, so a just-loaded profile
    /// shows this device's connection, not the synced column another
    /// device set. Applied to the baseline too, so the column is only
    /// written when the user toggles here. A device that predates the
    /// local flag adopts the synced value only if Health has asked it.
    private func adoptDeviceHealthConnection() {
        let synced = profile.healthConnected
        let local = HealthSyncSettings.isConnected
        profile.healthConnected = local ?? false
        persistedProfile?.healthConnected = local ?? false
        guard local == nil, synced else { return }
        Task { @MainActor [weak self] in
            let askedHere = await HealthKitService.shared.hasRequestedReadAuthorization()
            guard HealthSyncSettings.isConnected == nil else { return }
            HealthSyncSettings.setConnected(askedHere)
            guard askedHere, let self else { return }
            self.profile.healthConnected = true
            self.persistedProfile?.healthConnected = true
            await self.refreshWatchVitals()
        }
    }

    /// Atomically updates the user-customizable identity fields shown on the
    /// profile customization sheet. Whitespace is trimmed; `bio` collapses
    /// empty strings to "" so the profile JSON stays compact.
    func updateProfileIdentity(name: String, bio: String) {
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.bio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    /// Persists the user's training preferences. Called by the
    /// onboarding flow's Activity & schedule + Equipment access
    /// steps and by Profile → Training settings.
    func updateTrainingPreferences(_ prefs: TrainingPreferences) {
        profile.trainingPreferences = prefs
        save()
    }

    func updateAvatarImageData(_ data: Data?) {
        profile.avatarImageData = data
        save()
    }

    // MARK: - Habits

    /// All non-archived habits, ordered by their `sortIndex` so the
    /// user's drag-to-reorder order survives a relaunch.
    var activeHabits: [Habit] {
        profile.habits
            .filter { !$0.archived }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    func addHabit(_ habit: Habit) {
        var copy = habit
        if copy.sortIndex == 0 {
            // Append to the bottom by default — drag-reorder writes
            // a fresh index later.
            copy.sortIndex = (profile.habits.map(\.sortIndex).max() ?? 0) + 1
        }
        profile.habits.append(copy)
        save()
        Task { await rescheduleHabitReminders() }
    }

    func updateHabit(_ habit: Habit) {
        guard let idx = profile.habits.firstIndex(where: { $0.id == habit.id }) else { return }
        profile.habits[idx] = habit
        save()
        Task { await rescheduleHabitReminders() }
    }

    /// Removes the habit and every entry logged against it. The delete
    /// dialog promises exactly that, and a habit deleted for privacy
    /// shouldn't leave its history syncing through CloudKit.
    func deleteHabit(id: UUID) {
        profile.habits.removeAll { $0.id == id }
        profile.habitEntries.removeAll { $0.habitId == id }
        save()
        Task { await rescheduleHabitReminders() }
    }

    func reorderHabits(_ ordered: [Habit]) {
        for (index, habit) in ordered.enumerated() {
            if let i = profile.habits.firstIndex(where: { $0.id == habit.id }) {
                profile.habits[i].sortIndex = index
            }
        }
        save()
    }

    /// Toggle today's completion for a boolean habit, or bump the
    /// count by one for a countable habit (capped at target). For
    /// custom set-the-exact-value flows (e.g. "I drank 6 glasses"),
    /// use `setHabitEntry(habitId:date:value:)` directly.
    func toggleHabitEntry(habitId: UUID, on date: Date = Date()) {
        guard let habit = profile.habits.first(where: { $0.id == habitId }) else { return }
        let day = Calendar.current.startOfDay(for: date)
        // Capture completion state BEFORE the mutation so the celebration
        // fires only on the not-complete → complete transition.
        let wasCompleted = HabitsService.summary(for: habit, entries: profile.habitEntries, on: date).isCompletedToday
        let target = habit.targetValue ?? 1
        let existingIdx = profile.habitEntries.firstIndex {
            $0.habitId == habitId && Calendar.current.isDate($0.date, inSameDayAs: day)
        }
        if habit.isCountable {
            // Countable habit: increment by one toward the target. If
            // the user has already hit target, the next tap RESETS to
            // zero (audit M2 — original impl silently no-op'd past
            // target with no way back). Zero == remove the entry so
            // the array doesn't accumulate value-0 zombies (M1).
            if let idx = existingIdx {
                let current = profile.habitEntries[idx].value
                if current >= target {
                    profile.habitEntries.remove(at: idx)
                } else {
                    profile.habitEntries[idx].value = min(target, current + 1)
                }
            } else {
                profile.habitEntries.append(HabitEntry(habitId: habitId, date: day, value: 1))
            }
        } else {
            // Boolean habit: tap once to complete, again to un-complete.
            // Un-completing REMOVES the entry instead of writing 0 so
            // a noisy check/uncheck cycle doesn't accumulate zombie
            // rows in the array (audit M1).
            if let idx = existingIdx {
                profile.habitEntries.remove(at: idx)
            } else {
                profile.habitEntries.append(HabitEntry(habitId: habitId, date: day, value: 1))
            }
        }
        save()
        registerHabitCompletionCelebration(habit: habit, wasCompleted: wasCompleted, on: date)
        // Ticking a habit off drops today's reminder; un-ticking restores it.
        Task { await rescheduleHabitReminders() }
    }

    /// Set the exact value for a given day. Use for countable habits
    /// where the user wants to type "6 glasses" rather than tap +1
    /// six times. Value 0 = uncompleted (removes the entry to keep
    /// the storage compact).
    func setHabitEntry(habitId: UUID, date: Date, value: Int) {
        let day = Calendar.current.startOfDay(for: date)
        let habit = profile.habits.first { $0.id == habitId }
        let wasCompleted = habit.map {
            HabitsService.summary(for: $0, entries: profile.habitEntries, on: date).isCompletedToday
        } ?? false
        let existingIdx = profile.habitEntries.firstIndex {
            $0.habitId == habitId && Calendar.current.isDate($0.date, inSameDayAs: day)
        }
        if value <= 0 {
            if let idx = existingIdx { profile.habitEntries.remove(at: idx) }
        } else if let idx = existingIdx {
            profile.habitEntries[idx].value = value
        } else {
            profile.habitEntries.append(HabitEntry(habitId: habitId, date: day, value: value))
        }
        save()
        if let habit {
            registerHabitCompletionCelebration(habit: habit, wasCompleted: wasCompleted, on: date)
        }
        Task { await rescheduleHabitReminders() }
    }

    // MARK: - Momentum / Atlas Score

    /// Transient guard so the "perfect day" burst fires once per day per
    /// app session, not every time the user re-taps the last habit. Resets
    /// on relaunch — deliberately "you can be celebrated again tomorrow".
    @ObservationIgnored private var lastPerfectDayCelebratedKey: String?

    /// The user's current Atlas Score / level, derived from stored profile
    /// state. Cheap arithmetic, safe to read from a view body.
    var momentum: MomentumEngine.Snapshot {
        let earnedToday = (profile.lastMomentumAwardDay.map { Calendar.current.isDateInToday($0) } ?? false)
            ? profile.momentumAwardedToday
            : 0
        return MomentumEngine.snapshot(score: profile.atlasScore, todayEarned: earnedToday)
    }

    /// Best all-time streak across active habits — feeds the habit-streak
    /// achievements (which unlock once, so the all-time best is what counts).
    var bestHabitStreak: Int {
        activeHabits.reduce(0) { best, habit in
            max(best, HabitsService.summary(for: habit, entries: profile.habitEntries, frozenDayKeys: profile.streakFreezeDays).bestStreak)
        }
    }

    /// Count of completed habit-days across all habits (value > 0).
    var totalHabitCompletions: Int {
        profile.habitEntries.filter { $0.value > 0 }.count
    }

    /// True when every habit due today is completed (and at least one was
    /// due). Drives the "perfect day" celebration + achievement.
    func allHabitsDoneToday(on date: Date = Date()) -> Bool {
        // The summary's due flag, not the schedule's: a times-per-week
        // habit that met its target stops holding the perfect day open.
        let due = activeHabits
            .map { HabitsService.summary(for: $0, entries: profile.habitEntries, on: date) }
            .filter(\.isDueToday)
        guard !due.isEmpty else { return false }
        return due.allSatisfy(\.isCompletedToday)
    }

    /// Fires the habit-completion celebration on the not-complete → complete
    /// transition only. The bigger "perfect day" burst fires the first time
    /// a day's full slate is cleared (guarded so re-toggling doesn't spam it).
    private func registerHabitCompletionCelebration(habit: Habit, wasCompleted: Bool, on date: Date) {
        guard !isEphemeral else { return }
        let nowCompleted = HabitsService.summary(for: habit, entries: profile.habitEntries, on: date).isCompletedToday
        guard !wasCompleted, nowCompleted else { return }

        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let dayKey = "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
        let isFreshPerfectDay = allHabitsDoneToday(on: date) && lastPerfectDayCelebratedKey != dayKey
        if isFreshPerfectDay { lastPerfectDayCelebratedKey = dayKey }

        Haptics.success()
        CelebrationCenter.shared.celebrate(
            .habitComplete(tintHex: habit.tintHex, allHabitsDone: isFreshPerfectDay)
        )
    }

    /// Banks today's earned Atlas Score points, idempotently. Recomputes
    /// today's points and banks only the increase over what today already
    /// earned, so a CloudKit pull or a habit toggled off/on can't
    /// double-count or roll the score back. Routes a level-up to
    /// `CelebrationCenter`. Never calls `save()` — the in-flight debounced
    /// save persists these mutations (calling save would recurse through
    /// `scheduleAchievementCheck`).
    private func accrueMomentumIfNeeded() {
        guard !isEphemeral else { return }
        let today = Calendar.current.startOfDay(for: Date())

        let ledgerIsToday = profile.lastMomentumAwardDay.map {
            Calendar.current.isDate($0, inSameDayAs: today)
        } ?? false
        if !ledgerIsToday {
            profile.lastMomentumAwardDay = today
            profile.momentumAwardedToday = 0
        }

        let earnedToday = MomentumEngine.dailyPoints(momentumInputs())
        guard earnedToday > profile.momentumAwardedToday else {
            recordMomentumHistory(on: today)
            return
        }

        let delta = earnedToday - profile.momentumAwardedToday
        let previousLevel = MomentumEngine.level(for: profile.atlasScore)
        profile.momentumAwardedToday = earnedToday
        profile.atlasScore += delta
        let newLevel = MomentumEngine.level(for: profile.atlasScore)
        if newLevel > previousLevel {
            profile.atlasLevel = newLevel
            let tier = MomentumEngine.Tier.forLevel(newLevel)
            CelebrationCenter.shared.celebrate(
                .levelUp(level: newLevel, tier: tier)
            )
        } else {
            profile.atlasLevel = max(profile.atlasLevel, newLevel)
        }
        recordMomentumHistory(on: today)
    }

    private func momentumInputs() -> MomentumEngine.Inputs {
        let dueHabits = activeHabits
            .map { HabitsService.summary(for: $0, entries: profile.habitEntries) }
            .filter(\.isDueToday)
        let doneHabits = dueHabits.filter(\.isCompletedToday)
        let today = todayEntries
        return MomentumEngine.Inputs(
            habitsDone: doneHabits.count,
            habitsDue: dueHabits.count,
            doseEntriesToday: today.count,
            doseCompletedToday: today.filter(\.completed).count,
            hasNutritionTargets: profile.nutritionTargets != nil,
            mealLoggedToday: !mealEntries().isEmpty
        )
    }

    private func recordMomentumHistory(on day: Date) {
        let point = MomentumDayPoint(date: day, score: profile.atlasScore, earned: profile.momentumAwardedToday)
        if let idx = profile.momentumHistory.firstIndex(where: {
            Calendar.current.isDate($0.date, inSameDayAs: day)
        }) {
            if profile.momentumHistory[idx] != point {
                profile.momentumHistory[idx] = point
            }
        } else {
            profile.momentumHistory.append(point)
            if profile.momentumHistory.count > 120 {
                profile.momentumHistory.removeFirst(profile.momentumHistory.count - 120)
            }
        }
    }

    /// One-tap adoption of an onboarding-recommended starter stack. Creates a
    /// gentle 8-week protocol on a 5-days-on / 2-days-off cadence, mornings
    /// only — the most forgiving default. The user can edit it immediately.
    @discardableResult
    func adoptStarterProtocol(
        peptides: [Peptide],
        name: String = String(localized: "Starter Protocol")
    ) -> PeptideProtocol? {
        guard !peptides.isEmpty else { return nil }
        let schedule = ProtocolSchedule(
            daysOfWeek: [1, 2, 3, 4, 5],
            timesPerDay: 1,
            preferredTimes: ["8:00 AM"]
        )
        let proto = PeptideProtocol(
            id: UUID(),
            name: name,
            peptides: peptides,
            schedule: schedule,
            cycleLengthWeeks: 8,
            startDate: Date(),
            status: .active,
            notes: String(localized: "Generated from your onboarding goals. Review and adjust before starting.")
        )
        addProtocol(proto)
        return proto
    }

    /// Persists the current profile state. Call after direct property mutations
    /// via bindings (e.g. settings toggles) that bypass dedicated update methods.
    func persistProfile() {
        save()
    }

    // MARK: - Notifications

    /// Latest scheduling outcome so the UI can surface dropped reminders.
    /// `nil` means notifications haven't been scheduled this session yet.
    var notificationReport: ScheduleReport? {
        let report = NotificationService.shared.lastReport
        return report.requested == 0 && report.scheduled == 0 ? nil : report
    }

    /// Names of active protocols whose reminders were partially or fully dropped
    /// in the most recent reschedule. Empty when everything fit under the limit.
    var droppedReminderProtocolNames: [String] {
        let dropped = NotificationService.shared.lastReport.droppedProtocolIDs
        guard !dropped.isEmpty else { return [] }
        return protocols.filter { dropped.contains($0.id) }.map(\.name).sorted()
    }

    func rescheduleNotificationsIfEnabled() {
        guard profile.doseRemindersEnabled else { return }
        NotificationService.shared.scheduleNotifications(for: activeProtocols)
    }

    /// Re-plans habit reminders against the current habits and today's
    /// completions. Habit reminders are per-habit opt-in (gated on
    /// `Habit.reminderTime != nil`) rather than the global
    /// `doseRemindersEnabled` switch — setting a reminder time on a habit
    /// is already an explicit opt-in.
    func rescheduleHabitReminders() async {
        await NotificationService.shared.scheduleHabitReminders(for: activeHabits, entries: profile.habitEntries)
    }

    // MARK: - Persistence

    private var achievementCheckPending = false

    /// Coalesced persistence quiet-period. Rapid mutations (e.g. toggling
    /// several doses in quick succession) are batched into one disk write
    /// after this many milliseconds of silence. Widget + Watch sync run on
    /// the same cadence so they get one write instead of N.
    private static let saveDebounceMs: UInt64 = 350

    @ObservationIgnored private var pendingSaveTask: Task<Void, Never>?
    /// In-flight Spotlight reindex. Tracked so rapid mutations can
    /// cancel the previous Task before scheduling a new one — prevents
    /// out-of-order writes from overwriting the index with stale data.
    @ObservationIgnored private var reindexTask: Task<Void, Never>?

    private func save() {
        // Achievements are computed off in-memory state, not what's on disk —
        // run them immediately so the toast still feels instant.
        scheduleAchievementCheck()

        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int64(Self.saveDebounceMs)))
            guard let self, !Task.isCancelled else { return }
            // Cleared before the write so a CloudKit refresh waiting on
            // it can run once the save lands.
            self.pendingSaveTask = nil
            self.performSaveNow()
        }
    }

    /// Forces a synchronous flush of any pending save. Call from
    /// `scenePhase == .background` so the OS can suspend us safely.
    func flushPendingSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        performSaveNow()
    }

    // MARK: - Entry window + backfill

    /// Cold-launch entry window. 400 days covers every synchronous
    /// render surface — Today, the calendar month, the 13-week protocol
    /// detail, and streaks past a full year — while bounding the
    /// launch-path decode for long-lived accounts. Everything older
    /// arrives via `scheduleEntryBackfill` immediately after init, so
    /// exports and lifetime totals still see the full history.
    static let recentEntryWindowDays = 400

    static func recentEntryWindowStart(now: Date = Date()) -> Date {
        Calendar.current.date(
            byAdding: .day, value: -recentEntryWindowDays,
            to: Calendar.current.startOfDay(for: now)
        ) ?? now
    }

    @ObservationIgnored private var entryBackfillTask: Task<Void, Never>?

    /// Hydrates entries older than the launch window. High priority —
    /// the sooner the tail lands, the smaller the window in which a
    /// lifetime stat or an export could read a partial history.
    private func scheduleEntryBackfill(before cutoff: Date) {
        entryBackfillTask?.cancel()
        entryBackfillTask = Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self, !Task.isCancelled, !self.isEphemeral else { return }
            let older = self.repo.loadEntries(before: cutoff, resolvingFrom: self.entryPeptideIndex)
            guard !older.isEmpty, !Task.isCancelled, !self.isEphemeral else { return }
            let known = Set(self.entries.map(\.id))
            let missing = older.filter {
                !known.contains($0.id) && !self.pendingProtocolDeletions.contains($0.protocolId)
            }
            guard !missing.isEmpty else { return }
            // Append-only merge: the backfill by construction holds only
            // rows outside the in-memory window, so nothing the user
            // touched since launch can be overwritten.
            //
            // These rows are already on disk — that's where they came
            // from — so the append must not mark `entries` dirty and
            // drag the whole history back through the next upsert. Any
            // dirt that was already there is preserved.
            let wasDirty = self.entriesNeedSave
            self.entries.append(contentsOf: missing)
            self.entriesNeedSave = wasDirty
        }
    }

    /// Test-only synchronous wait for the backfill (async by design in
    /// production).
    func awaitEntryBackfillForTesting() async {
        await entryBackfillTask?.value
    }

    private func performSaveNow() {
        // Ephemeral mode (screenshot capture) — never write to disk.
        // The demo state lives entirely in memory and dies when the
        // user flips the toggle off + reloadFromDisk restores the
        // real data.
        guard !isEphemeral else { return }

        // Upsert + explicit-delete pattern. Previously this called
        // saveProtocols(self.protocols) / saveEntries(self.entries)
        // which used a "delete-everything-not-in-input" diff. When
        // CloudKit delivered a remote insert between the last
        // reloadFromDisk and now, that row was absent from the local
        // arrays and would be silently deleted (and the deletion
        // propagated back to CloudKit). Explicit deletion tracking
        // closes that window: only IDs that DataStore actually
        // intended to remove are deleted.
        // Nothing changed since the last successful save — most often a
        // background transition on an untouched app. Returning here also
        // skips the widget-timeline reload below, which the OS budgets.
        guard protocolsNeedSave || entriesNeedSave || profileNeedsSave
                || !pendingProtocolDeletions.isEmpty || !pendingEntryDeletions.isEmpty
        else { return }

        repo.beginSaveBatch()
        if protocolsNeedSave || entriesNeedSave { dropProtocolsDeletedElsewhere() }
        if protocolsNeedSave { repo.upsertProtocols(protocols) }
        if entriesNeedSave {
            let deletedElsewhere = repo.upsertEntries(entries)
            if !deletedElsewhere.isEmpty { entries.removeAll { deletedElsewhere.contains($0.id) } }
        }
        for id in pendingProtocolDeletions {
            repo.deleteProtocol(id: id)
            // Includes rows outside the in-memory window or synced in
            // since the last load, which the explicit ids miss.
            repo.deleteEntries(protocolId: id)
        }
        if !pendingEntryDeletions.isEmpty {
            // A regenerated dose reuses its slot's id; a row still in
            // memory is never deleted.
            let liveIDs = Set(entries.map(\.id))
            repo.deleteEntries(ids: pendingEntryDeletions.subtracting(liveIDs))
        }
        if profileNeedsSave {
            if persistedProfile == nil, let stored = repo.loadProfile() {
                // Launch found no profile row, but CloudKit has imported
                // the account's since: merge this device's fresh profile
                // into it instead of overwriting the user's history.
                profile = ProfileMergeEngine.reconcile(profile, with: stored)
            }
            repo.saveProfile(profile, since: persistedProfile)
        }

        // Surface a banner if any commit in this batch failed — a
        // disk-full / locked-store save would otherwise drop the
        // user's latest change with no visible signal. Clear the
        // banner once a save succeeds, but never clobber the more
        // serious init-time "Storage unavailable" messages.
        if repo.commitDidFail {
            lastError = Self.saveFailureMessage
            // Persistence failed — the in-memory state is ahead of the
            // store. Do NOT push it to the widget/Watch projections: after
            // a relaunch the app reloads the older persisted state, and a
            // projection written now would show "completed" for a dose the
            // source of truth never recorded. The banner above tells the
            // user; the projections keep their last-good snapshot.
            return
        }
        // Committed — everything in memory is now on disk. Deletions are
        // drained here rather than above so a failed batch re-attempts
        // them too; deleting an already-deleted row is a no-op.
        protocolsNeedSave = false
        entriesNeedSave = false
        profileNeedsSave = false
        persistedProfile = profile
        pendingProtocolDeletions.removeAll()
        pendingEntryDeletions.removeAll()

        if lastError == Self.saveFailureMessage {
            lastError = nil
        }

        updateWidgetData()
        updateWatchData()
    }

    /// A protocol another device deleted, whose CloudKit import landed
    /// before this device reloaded, leaves memory here instead of being
    /// re-inserted (with today's doses) by this save.
    private func dropProtocolsDeletedElsewhere() {
        let deletedElsewhere = repo.protocolIDsDeletedElsewhere(among: Set(protocols.map(\.id)))
        guard !deletedElsewhere.isEmpty else { return }
        protocols.removeAll { deletedElsewhere.contains($0.id) }
        entries.removeAll { deletedElsewhere.contains($0.protocolId) }
    }

    /// Banner copy for a transient live-save failure. Kept as a
    /// constant so `performSaveNow` can both set and clear exactly
    /// this message without disturbing other `lastError` states.
    static let saveFailureMessage = String(localized: "Couldn't save your latest changes — your device may be low on storage.")

    // MARK: - Ephemeral / screenshot mode

    /// Swaps the in-memory state for a demo seed and locks writes
    /// so user data on disk stays untouched. Called by
    /// `ScreenshotMode.activate(in:)` on a toggle flip and on
    /// every cold launch where the flag is already on.
    ///
    /// Bumps `cacheVersion` so every derived metric (streak,
    /// weeklyCompletion, topInsight) recomputes against the new
    /// state on the next read — without the bump, cached values
    /// from before the swap would survive and the screenshots
    /// would render with stale stats.
    func enterEphemeralMode(
        profile newProfile: UserProfile,
        protocols newProtocols: [PeptideProtocol],
        entries newEntries: [ProtocolEntry]
    ) {
        isEphemeral = true
        // A late-landing backfill would append real history on top of
        // the demo seed mid-screenshot.
        entryBackfillTask?.cancel()
        self.profile = newProfile
        self.protocols = newProtocols
        self.entries = newEntries
        cacheVersion &+= 1
        widgetWorkouts = nil
        // Refresh widget + watch surfaces so the lock-screen
        // accessory + Watch Today page render the demo numbers
        // for the screenshots. Safe to call even though
        // `performSaveNow` is gated — these accessory updaters
        // are independent of the JSON sidecars.
        updateWidgetData()
        updateWatchData()
    }

    /// Drops the ephemeral lock and reloads real data from disk
    /// so the user is back to where they left off before the
    /// screenshot session.
    func exitEphemeralMode() {
        isEphemeral = false
        reloadFromDisk()
    }

    /// Builds a snapshot via `WidgetSnapshotBuilder` and pushes it through
    /// the persistence + WidgetCenter side effects. The pure transform
    /// lives in the builder so a snapshot regression is testable without
    /// standing up `DataStore` + `PersistenceService`. Nutrition is
    /// pulled live from the profile so the nutrition widget reflects
    /// the same numbers the Meals tab shows.
    #if DEBUG
    /// Test-only observability: bumped every time a projection push
    /// actually runs, so tests can assert the widget/Watch surfaces were
    /// (or were not) updated without reaching into the App Group
    /// container or a live WCSession.
    @ObservationIgnored private(set) var widgetUpdateCountForTesting = 0
    @ObservationIgnored private(set) var watchUpdateCountForTesting = 0
    #endif
    /// The payload last written to the App Group container.
    @ObservationIgnored private var lastWidgetData: WidgetData?
    @ObservationIgnored private var widgetWorkouts: [WorkoutSession]?

    /// Last recovery + sleep glance pushed to the Watch. HealthKit is
    /// async-only and `updateWatchData()` is sync, so the snapshot is
    /// cached here and carried on every push until the next refresh.
    /// Seeded from the last push so a save at launch doesn't blank it.
    @ObservationIgnored private var watchVitals: WatchVitalsSnapshot? = WatchSyncService.lastWrittenVitals()

    /// Re-reads HRV, resting heart rate and last night's sleep, then
    /// pushes them to the Watch. Runs on app activation and when Health
    /// is connected or disconnected.
    func refreshWatchVitals() async {
        guard profile.healthConnected else {
            guard watchVitals != nil else { return }
            watchVitals = nil
            updateWatchData()
            return
        }
        let vitals = await Self.buildWatchVitals(sleepTargetHours: RecoveryScoreEngine.defaultSleepTargetHours)
        guard profile.healthConnected else { return }
        watchVitals = vitals
        updateWatchData()
    }

    private static func buildWatchVitals(sleepTargetHours: Double) async -> WatchVitalsSnapshot? {
        let kit = HealthKitService.shared
        async let recentHRV = kit.averageHRV(days: 3)
        async let baseHRV = kit.averageHRV(days: 30)
        async let recentRHR = kit.averageRestingHeartRate(days: 3)
        async let baseRHR = kit.averageRestingHeartRate(days: 30)
        async let lastSleepHours = kit.lastNightSleepHours()
        async let segments = kit.recentSleepSegments()

        let hrv = await recentHRV
        let hrvBaseline = await baseHRV
        let rhr = await recentRHR
        let rhrBaseline = await baseRHR
        let sleepHours = await lastSleepHours
        let night = SleepScoreEngine.night(from: await segments)

        // Same inputs `HeroMetricSnapshot.build` uses, so the wrist and
        // the iPhone's Today screen show the same Recovery number.
        let recovery = RecoveryScoreEngine.score(inputs: .init(
            recentHRV: hrv,
            baselineHRV: hrvBaseline,
            recentRHR: rhr,
            baselineRHR: rhrBaseline,
            lastSleepHours: sleepHours,
            sleepTargetHours: sleepTargetHours
        ))
        let sleep = night.map { night in
            WatchSleepSnapshot(
                score: SleepScoreEngine.score(night, targetHours: sleepTargetHours),
                start: night.start,
                end: night.end,
                deepMinutes: Int((night.deep / 60).rounded()),
                coreMinutes: Int((night.core / 60).rounded()),
                remMinutes: Int((night.rem / 60).rounded()),
                unspecifiedMinutes: Int((night.unspecified / 60).rounded()),
                awakeMinutes: Int((night.awake / 60).rounded())
            )
        }
        let snapshot = WatchVitalsSnapshot(
            recoveryScore: recovery?.value,
            restingHeartRate: rhr.map { Int($0.rounded()) },
            restingHeartRateBaseline: rhrBaseline.map { Int($0.rounded()) },
            hrv: hrv.map { Int($0.rounded()) },
            hrvBaseline: hrvBaseline.map { Int($0.rounded()) },
            sleep: sleep,
            measuredAt: Date()
        )
        let hasAnything = snapshot.recoveryScore != nil
            || snapshot.restingHeartRate != nil
            || snapshot.hrv != nil
            || sleep != nil
        return hasAnything ? snapshot : nil
    }

    private func updateWidgetData() {
        #if DEBUG
        widgetUpdateCountForTesting += 1
        #endif
        let data = WidgetSnapshotBuilder.build(
            today: todayEntries,
            next: nextDose,
            hasActiveProtocol: !activeProtocols.isEmpty,
            consumption: LifestyleDataLogic.consumption(in: profile, for: Date()),
            targets: profile.nutritionTargets,
            breakdown: LifestyleDataLogic.mealsByCategory(in: profile, for: Date()),
            workouts: recentWidgetWorkouts(),
            activeWorkout: WorkoutSessionService.shared.activeSession,
            unit: profile.bodyMetrics.unit
        )
        if let lastWidgetData, data.hasSameContent(as: lastWidgetData) { return }
        // Remembered only once written: a failed write must not make the
        // next identical payload look like a no-op.
        guard PersistenceService.shared.updateWidgetData(data) else { return }
        lastWidgetData = data
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Newest-first and bounded: 30 sessions covers the current week plus
    /// the last finished workout for any user. Cached because most widget
    /// pushes follow dose and meal saves that leave workouts untouched;
    /// `refreshTrainingGlanceables` drops the cache after workout writes.
    /// The builder filters the in-progress session out.
    private func recentWidgetWorkouts() -> [WorkoutSession] {
        if let widgetWorkouts { return widgetWorkouts }
        let loaded = repo.loadWorkoutSessions(limit: 30)
        widgetWorkouts = loaded
        return loaded
    }

    /// Pushes a snapshot through `WatchSyncService`. Math (compliance
    /// fraction, lifetime total) is delegated to `EntryAnalytics` so the
    /// definitions are shared with any future watch / widget / share-card
    /// surface that needs the same numbers.
    private func updateWatchData() {
        #if DEBUG
        watchUpdateCountForTesting += 1
        #endif
        // Surface the same stats the Stats page on the watch reads —
        // streak, week compliance, total logged — plus the Atlas Score
        // and today's health/training habit split for the Watch
        // complications. The watch carries every field forward as an
        // optional so an older phone build (without these in the JSON)
        // still decodes cleanly.
        let snap = momentum
        let dueHabits = activeHabits.filter { $0.schedule.isDue(on: Date()) }
        let healthDue = dueHabits.filter { $0.category == .health }
        let trainingDue = dueHabits.filter { $0.category == .fitness }
        func isDone(_ habit: Habit) -> Bool {
            HabitsService.summary(for: habit, entries: profile.habitEntries).isCompletedToday
        }
        WatchSyncService.shared.updateWatchData(
            entries: entries,
            protocols: protocols,
            currentStreak: currentStreak,
            weeklyCompliance: EntryAnalytics.weeklyComplianceFraction(in: entries, protocols: protocols),
            totalDosesLogged: EntryAnalytics.totalDosesLogged(in: entries),
            nutrition: nutritionSnapshotForWatch(),
            atlasScore: snap.score,
            atlasLevel: snap.level,
            atlasTier: snap.tier.rawValue,
            atlasProgress: snap.progressInLevel,
            atlasTodayEarned: snap.todayEarned,
            healthHabitsDone: healthDue.filter(isDone).count,
            healthHabitsTotal: healthDue.count,
            trainingHabitsDone: trainingDue.filter(isDone).count,
            trainingHabitsTotal: trainingDue.count,
            measurementUnit: profile.bodyMetrics.unit.rawValue,
            healthConnected: profile.healthConnected,
            vitals: watchVitals,
            workout: watchWorkout,
            training: WatchWorkoutSnapshotBuilder.training(from: recentWidgetWorkouts()),
            hapticsEnabled: profile.hapticFeedbackEnabled
        )
    }

    /// Build the compact nutrition snapshot the Watch app renders.
    /// Returns nil when the user has no nutrition targets and no
    /// meal-logging streak — there's nothing meaningful to show,
    /// and a nil keeps the Watch UI from displaying empty rings.
    private func nutritionSnapshotForWatch() -> WatchNutritionSnapshot? {
        let consumption = LifestyleDataLogic.consumption(in: profile, for: Date())
        let streak = LifestyleDataLogic.mealLoggingStreak(in: profile)
        let entryCount = LifestyleDataLogic.mealEntries(in: profile, for: Date()).count
        let targets = profile.nutritionTargets

        // Suppress the page only when there's truly nothing to read.
        // A user who logged a zero-calorie entry (rare, but possible
        // — black coffee with manual macro override) still gets the
        // page so the entry count signals "I logged something".
        let nothingToShow =
            targets == nil
            && consumption.caloriesKcal == 0
            && streak == 0
            && entryCount == 0
        guard !nothingToShow else { return nil }

        return WatchNutritionSnapshot(
            caloriesToday: consumption.caloriesKcal,
            calorieTarget: targets?.calories ?? 0,
            proteinToday: consumption.proteinG,
            proteinTarget: targets?.proteinG ?? 0,
            mealLoggingStreak: streak,
            mealEntriesToday: entryCount
        )
    }


    /// Achievements are stored per install while the records they count
    /// come back from iCloud, so a reinstall's first check would replay
    /// every earned unlock as a toast. Seeds silently once, after the
    /// entry backfill so lifetime totals are complete.
    private func seedAchievementsIfNeeded() {
        guard AchievementService.shared.needsSilentSeed else { return }
        let backfill = entryBackfillTask
        Task { @MainActor [weak self] in
            await backfill?.value
            guard let self, !self.isEphemeral else { return }
            AchievementService.shared.seedSilently {
                self.runAchievementChecks()
                AchievementService.shared.checkTrainingAchievements(
                    workoutCount: self.repo.workoutSessionCount(),
                    prDetected: false
                )
            }
        }
    }

    private func scheduleAchievementCheck() {
        guard !achievementCheckPending else { return }
        achievementCheckPending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.achievementCheckPending = false
            // The silent seed covers the current state; checking first
            // would toast everything it is about to absorb.
            if !AchievementService.shared.needsSilentSeed {
                self.runAchievementChecks()
            }
            // Bank today's Atlas Score from the same coalesced hook. Mutates
            // the profile in memory; the debounced save persists it.
            self.accrueMomentumIfNeeded()
        }
    }

    private func runAchievementChecks() {
        AchievementService.shared.checkAchievements(
            totalDoses: self.totalDoses,
            currentStreak: self.currentStreak,
            bestStreak: self.bestStreak,
            protocolCount: self.protocols.count,
            daysLogged: self.totalDaysLogged
        )
        // Lifestyle and habit milestones run on the same hook; every
        // unlock joins one FIFO toast queue.
        AchievementService.shared.checkLifestyleAchievements(
            mealsLogged: self.profile.mealHistory.count,
            mealStreak: self.mealLoggingStreak,
            labsLogged: self.profile.labHistory.count,
            labPanelCount: Set(self.profile.labHistory.map(\.panel)).count,
            recipesCount: self.profile.recipes.count,
            checkInsLogged: self.profile.outcomeHistory.count
        )
        AchievementService.shared.checkHabitAchievements(
            habitCount: self.activeHabits.count,
            bestHabitStreak: self.bestHabitStreak,
            totalCompletions: self.totalHabitCompletions,
            perfectDayToday: self.allHabitsDoneToday(),
            perfectWeek: (HabitsService.completionRate(
                habits: self.activeHabits,
                entries: self.profile.habitEntries,
                days: 7
            ) ?? 0) >= 1.0
        )
    }

    /// Idempotent: appends today's scheduled entries for any active protocol that
    /// doesn't already have one for today. Safe to call any time the user opens
    /// the app — handles cold launch and day rollovers without duplicating.
    func regenerateTodayEntries() {
        let calendar = Calendar.current
        let existingProtocolIds = Set(
            entries.filter { calendar.isDateInToday($0.date) }.map(\.protocolId)
        )
        var added = false
        for proto in activeProtocols where !existingProtocolIds.contains(proto.id) {
            entries.append(contentsOf: Self.generateTodayEntries(for: proto))
            added = true
        }
        if added { save() }
    }

    /// Called when the app becomes active. Detects calendar-day changes since the
    /// last check and regenerates today's entries when needed. Idempotent.
    func handleAppActivation() {
        bumpVersionIfDayChanged()
        // Flip any `.active` protocols past the soft auto-complete
        // threshold to `.completed`. Runs BEFORE regenerateTodayEntries
        // so the just-completed cycles don't produce another day of
        // scheduled entries before the status change lands.
        performCycleAutoCompletion()
        regenerateTodayEntries()
        refreshHealthIfDue()
        turnOffDeniedHealthWrites()
        // The unlock notification isn't delivered to a suspended app.
        retryUnreadableCustomPeptides()
    }

    /// Write access can be withdrawn in Settings at any time; a toggle
    /// left on would only make every write fail in the log.
    private func turnOffDeniedHealthWrites() {
        let health = HealthKitService.shared
        if HealthSyncSettings.isNutritionEnabled, health.isNutritionWriteDenied {
            UserDefaults.standard.set(false, forKey: HealthSyncSettings.nutritionEnabledKey)
        }
        if HealthSyncSettings.isEnabled, health.isActivityWriteDenied {
            UserDefaults.standard.set(false, forKey: HealthSyncSettings.enabledKey)
        }
    }

    private func refreshHealthIfDue() {
        let now = Date()
        if let last = lastHealthRefresh,
           now.timeIntervalSince(last) < Self.healthRefreshInterval,
           Calendar.current.isDate(last, inSameDayAs: now) { return }
        lastHealthRefresh = now
        Task { await refreshWatchVitals() }
        Task { await importHealthWeights() }
    }

    /// Pull-to-refresh. Lands pending edits first, so the reload can't
    /// discard them or bring back a protocol whose deletion is still
    /// queued; while they can't be saved, memory stays as it is.
    func refreshFromStore() {
        flushPendingSave()
        guard !hasUnsavedChanges else { return }
        reloadFromDisk()
    }

    /// Re-pulls protocols / entries / profile from the repository so a
    /// CloudKit sync from another device shows up without an app
    /// relaunch. Falls back to the existing in-memory state if the repo
    /// returns nil for that resource. Replaces unsaved in-memory edits;
    /// user-triggered refreshes go through `refreshFromStore`.
    func reloadFromDisk() {
        // Same two-phase shape as init: the recent window synchronously
        // (this runs on pull-to-refresh and CloudKit pulls, where a
        // full-table decode would jank the refresh gesture), the tail
        // backfilled immediately after.
        let entryWindowStart = Self.recentEntryWindowStart()
        protocols = repo.loadProtocols()
        entries = repo.loadEntries(onOrAfter: entryWindowStart, resolvingFrom: entryPeptideIndex)
        if repo.entryCount() > entries.count {
            scheduleEntryBackfill(before: entryWindowStart)
        }
        let saved = repo.loadProfile()
        persistedProfile = saved
        if let saved {
            profile = saved
            adoptDeviceHealthConnection()
            // Only clear the profile flag when a row actually replaced
            // it — otherwise an unsaved in-memory profile edit would be
            // marked clean without ever reaching disk.
            profileNeedsSave = false
        }
        // Protocols and entries always came straight from disk, so the
        // assignments above must not leave them marked dirty — the next
        // save would write back the rows it just read. Cleared before
        // `regenerateTodayEntries`, which can legitimately add today's
        // rows and re-dirties `entries` when it does.
        protocolsNeedSave = false
        entriesNeedSave = false
        regenerateTodayEntries()
        // Routines and fasts from another device (or the new iCloud
        // account) would otherwise show only once their screen next
        // appears — a fast started or ended elsewhere would leave the
        // Meals card, and its end-of-fast reminder, stale.
        RoutineStore.shared.load()
        FastingStore.shared.load()
        ExerciseLibrary.shared.reloadCustomExercises()
        // CloudKit-driven pulls land here; without these the lock-
        // screen widget and the Watch tab would stay stale until the
        // next user mutation or the widget's 15-min auto-timer.
        refreshTrainingGlanceables()
        // A protocol added, paused or re-timed on another device, or a
        // habit reminder changed there, would otherwise keep this
        // device's old reminders until the next local edit.
        rescheduleNotificationsIfEnabled()
        Task { await rescheduleHabitReminders() }
    }

    /// Transactionally applies a backup import — the user has
    /// already confirmed the Replace / Merge choice and seen a
    /// validation preview. Plan E's commit phase.
    ///
    /// The mutation is atomic from the user's perspective: the
    /// in-memory state is replaced in one assignment, the repo is
    /// updated via the same upsert path the live save uses, and
    /// pending deletion sets are cleared so the next save doesn't
    /// inadvertently delete CloudKit-side data that came in via
    /// the restore.
    // MARK: - Backup accessors

    // Read-through accessors for the backup pipeline. ExportSection and
    // BackupImportService need the full training store, and `repo` is
    // private by design — these keep the single-facade rule intact
    // instead of handing views the repository singleton.
    func allWorkoutSessionsForBackup() -> [WorkoutSession] { repo.loadAllWorkoutSessions() }
    /// `fetchCount` only, so the export screen can gate its workout row
    /// without decoding every session.
    var hasWorkoutHistory: Bool { repo.workoutSessionCount() > 0 }
    func routinesForBackup() -> [Routine] { repo.loadRoutines() }
    func customExercisesForBackup() -> [CustomExercise] { repo.loadCustomExercises() }
    func personalRecordsForBackup() -> [PersonalRecord] { repo.loadPersonalRecords() }

    func applyImport(
        protocols newProtocols: [PeptideProtocol],
        entries newEntries: [ProtocolEntry],
        profile newProfile: UserProfile,
        training: BackupImportService.TrainingImport? = nil
    ) throws {
        guard !isEphemeral else {
            throw NSError(
                domain: "Peptide.BackupImport",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "Backup import is disabled in screenshot/demo mode."]
            )
        }

        // Drop any pending deletion bookkeeping — those IDs belong to
        // the pre-import world and would otherwise propagate as
        // CloudKit deletions against the just-restored rows. Same for
        // an in-flight entry backfill: its rows predate the import and
        // must not be appended on top of the restored state.
        entryBackfillTask?.cancel()
        pendingProtocolDeletions.removeAll()
        pendingEntryDeletions.removeAll()

        // Replace in-memory state first so any observers (Train tab,
        // calendar, etc.) re-render against the new data while the
        // disk write is in flight.
        protocols = newProtocols
        entries = newEntries
        profile = newProfile

        // Bulk write. For protocols + entries, use the upsert APIs +
        // explicit deletes for any IDs that the import dropped.
        // saveProfile is the simple replace.
        let liveProtocolIDs = Set(repo.loadProtocols().map(\.id))
        let importProtocolIDs = Set(newProtocols.map(\.id))
        let liveEntryIDs = Set(repo.loadEntryIDs())
        let importEntryIDs = Set(newEntries.map(\.id))

        repo.beginSaveBatch()
        repo.forgetPersistedIDs()
        repo.upsertProtocols(newProtocols)
        repo.upsertEntries(newEntries)

        // Anything in the live store that the import didn't carry =
        // user intent to remove. Used by the Replace path; Merge
        // never produces these because the merge logic kept current
        // IDs intact upstream.
        let droppedProtocolIDs = liveProtocolIDs.subtracting(importProtocolIDs)
        for id in droppedProtocolIDs {
            repo.deleteProtocol(id: id)
        }
        let droppedEntryIDs = liveEntryIDs.subtracting(importEntryIDs)
        if !droppedEntryIDs.isEmpty {
            repo.deleteEntries(ids: droppedEntryIDs)
        }

        repo.saveProfile(newProfile)

        // v2 training + custom-peptide payload. `nil` = the backup
        // predates these sections; leave the live stores untouched.
        if let training {
            let liveSessionIDs = Set(repo.loadAllWorkoutSessions().map(\.id))
            let liveRoutineIDs = Set(repo.loadRoutines().map(\.id))
            let liveExerciseIDs = Set(repo.loadCustomExercises().map(\.id))
            let liveRecordIDs = Set(repo.loadPersonalRecords().map(\.exerciseID))

            for session in training.workoutSessions { repo.upsertWorkoutSession(session) }
            for routine in training.routines { repo.upsertRoutine(routine) }
            for exercise in training.customExercises { repo.upsertCustomExercise(exercise) }
            for record in training.personalRecords { repo.upsertPersonalRecord(record) }

            if training.deletesUncarried {
                for id in liveSessionIDs.subtracting(training.workoutSessions.map(\.id)) {
                    repo.deleteWorkoutSession(id: id)
                }
                for id in liveRoutineIDs.subtracting(training.routines.map(\.id)) {
                    repo.deleteRoutine(id: id)
                }
                for id in liveExerciseIDs.subtracting(training.customExercises.map(\.id)) {
                    repo.deleteCustomExercise(id: id)
                }
                for id in liveRecordIDs.subtracting(training.personalRecords.map(\.exerciseID)) {
                    repo.deletePersonalRecord(exerciseID: id)
                }
            }

            customPeptides = training.customPeptides
            PersistenceService.shared.saveCustomPeptides(training.customPeptides)
            RoutineStore.shared.load()
            ExerciseLibrary.shared.reloadCustomExercises()

            // Training rows bypass the `protocols`/`entries`/`profile`
            // didSet bumps, same as recordWorkoutFinished — bump so
            // Train/Today snapshots recompute against the restored data.
            cacheVersion &+= 1
            revision &+= 1
        }

        // A failed commit leaves the restored state dirty in memory, so
        // the next save retries the write instead of reporting success.
        if repo.commitDidFail {
            lastError = Self.saveFailureMessage
            throw NSError(
                domain: "Peptide.BackupImport",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey:
                    "The restore couldn't be saved — your device may be low on storage."]
            )
        }
        // Everything assigned above is now on disk; left dirty, the next
        // save would upsert the whole restore a second time.
        protocolsNeedSave = false
        entriesNeedSave = false
        profileNeedsSave = false
        persistedProfile = newProfile

        regenerateTodayEntries()
        refreshTrainingGlanceables()
        rescheduleNotificationsIfEnabled()
    }

    // MARK: - Entry Generation

    private static func generateInitialEntries(for protocols: [PeptideProtocol]) -> [ProtocolEntry] {
        let calendar = Calendar.current
        var allEntries: [ProtocolEntry] = []

        for proto in protocols {
            let historical = MockEntries.generateEntries(for: proto, days: 30)
                .filter { !calendar.isDateInToday($0.date) }
            allEntries.append(contentsOf: historical)
            allEntries.append(contentsOf: generateTodayEntries(for: proto))
        }

        return allEntries
    }

    private static func generateTodayEntries(for proto: PeptideProtocol) -> [ProtocolEntry] {
        guard proto.status == .active else { return [] }
        return proto.peptides.flatMap { todayEntries(for: $0, in: proto) }
    }

    /// Locale-stable parser for the "h:mm a" times we store in
    /// `ProtocolSchedule.preferredTimes`. Hoisted to `static let` so we don't
    /// pay the ~1ms `DateFormatter` allocation on every dose generation —
    /// `todayEntries(for:in:)` runs once per peptide on every entry mutation.
    private static let timeStringParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func todayEntries(for peptide: Peptide, in proto: PeptideProtocol) -> [ProtocolEntry] {
        guard proto.status == .active else { return [] }

        let schedule = proto.schedule(for: peptide.id)
        let calendar = Calendar.current
        // Wash-out days have nothing due — the calendar, cycle bands and
        // adherence already agree on that, so Today must not generate them.
        guard CyclePhaseEngine.isOnCycle(Date(), protocol: proto, calendar: calendar),
              schedule.isActive(on: Date(), protocolStart: proto.startDate, calendar: calendar)
        else { return [] }

        return schedule.preferredTimes.compactMap { timeString in
            guard let time = timeStringParser.date(from: timeString) else { return nil }
            let hour = calendar.component(.hour, from: time)
            let minute = calendar.component(.minute, from: time)
            let entryDate: Date
            if let resolved = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) {
                entryDate = resolved
            } else {
                // The wall-clock time doesn't exist today (DST gap) —
                // fall back to a deterministic offset from start-of-day
                // rather than `Date()`, which would mis-time the dose
                // to the current moment.
                entryDate = calendar.startOfDay(for: Date())
                    .addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
            }
            return ProtocolEntry(
                id: ProtocolEntry.scheduledID(
                    protocolId: proto.id, peptideId: peptide.id, date: entryDate, calendar: calendar
                ),
                protocolId: proto.id,
                peptide: peptide,
                date: entryDate,
                dose: schedule.resolvedDose,
                notes: "",
                completed: false
            )
        }
    }

    private func appendTodayEntries(for proto: PeptideProtocol) {
        let calendar = Calendar.current
        let alreadyHasToday = entries.contains {
            $0.protocolId == proto.id && calendar.isDateInToday($0.date)
        }
        guard !alreadyHasToday else { return }
        let newEntries = Self.generateTodayEntries(for: proto)
        entries.append(contentsOf: newEntries)
    }
}
