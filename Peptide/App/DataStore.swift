import SwiftUI
import WidgetKit

@MainActor @Observable
final class DataStore: DataServiceProtocol {
    var protocols: [PeptideProtocol] {
        didSet { cacheVersion &+= 1 }
    }
    var entries: [ProtocolEntry] {
        didSet { cacheVersion &+= 1 }
    }
    var profile: UserProfile
    var customPeptides: [Peptide]

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
    private let _peptideDatabase: [Peptide] = PeptideDatabase.shared

    // MARK: - Cache (avoids recomputing expensive stats on every toggle)
    //
    // Each cached field stores the cacheVersion it was computed at. didSet on
    // `protocols`/`entries` increments cacheVersion automatically — readers
    // recompute when their stored version is stale. `bumpVersionIfDayChanged`
    // covers caches that depend on "today" (todayEntries, weeklyCompletion,
    // streaks) so they invalidate on midnight rollover.
    @ObservationIgnored private var cacheVersion: Int = 0
    @ObservationIgnored private var versionedDay: Date = Calendar.current.startOfDay(for: Date())

    @ObservationIgnored private var _todayEntries: (version: Int, value: [ProtocolEntry])?
    @ObservationIgnored private var _currentStreak: (version: Int, value: Int)?
    @ObservationIgnored private var _totalDaysLogged: (version: Int, value: Int)?
    @ObservationIgnored private var _bestStreak: (version: Int, value: Int)?
    @ObservationIgnored private var _nextDose: (version: Int, value: ProtocolEntry?)?
    @ObservationIgnored private var _weeklyCompletion: (version: Int, value: [WeekDayStatus])?
    @ObservationIgnored private var _entriesByDay: (version: Int, value: [Date: [ProtocolEntry]])?
    @ObservationIgnored private var _stackPeptides: (version: Int, value: [Peptide])?
    @ObservationIgnored private var _stackWarnings: (version: Int, value: [StackRecommendationEngine.Warning])?
    @ObservationIgnored private var _stackRecommendations: (version: Int, value: [StackRecommendationEngine.Recommendation])?
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
    /// the per-day stats (currentStreak, totalDaysLogged, weeklyCompletion,
    /// InsightsView complianceData / weeklyDoseData) share one O(n) group
    /// pass per mutation instead of re-filtering the entries array per day.
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
        let activeIds = Set(activeProtocols.map(\.id))
        return entriesByDay.compactMapValues { dayEntries -> [ProtocolEntry]? in
            let filtered = dayEntries.filter { activeIds.contains($0.protocolId) }
            return filtered.isEmpty ? nil : filtered
        }
    }

    init(seedSampleData: Bool = false) {
        // Initialize ALL stored properties first so Swift's two-phase init
        // is satisfied before any method calls on self.
        self.repo      = SwiftDataRepository.shared
        self.protocols = []
        self.entries   = []
        self.profile   = .fresh
        self.customPeptides = PersistenceService.shared.loadCustomPeptides() ?? []

        // Phase 2: self is fully initialized — safe to call methods.
        if repo.isInoperable {
            self.lastError = "Storage unavailable — please reinstall the app to restore data persistence."
        } else if repo.isUsingFallbackStore {
            self.lastError = "Storage unavailable — changes won't be saved between launches."
        }
        let savedProtocols = repo.loadProtocols()
        let savedEntries   = repo.loadEntries()
        let savedProfile   = repo.loadProfile()

        if !savedProtocols.isEmpty || !savedEntries.isEmpty || savedProfile != nil {
            // Returning user: recover what we can. Using || (not &&) so a single
            // corrupt record doesn't erase the user's entire dataset.
            self.protocols = savedProtocols
            self.entries   = savedEntries
            self.profile   = savedProfile ?? .fresh
            regenerateTodayEntries()
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

    var peptideDatabase: [Peptide] { _peptideDatabase + customPeptides }

    func addCustomPeptide(_ peptide: Peptide) {
        customPeptides.append(peptide)
        PersistenceService.shared.saveCustomPeptides(customPeptides)
        if profile.hapticFeedbackEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
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
        if profile.hapticFeedbackEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    func deleteProtocol(id: UUID) {
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
        if status == .active {
            let currentActive = protocols.filter {
                $0.status == .active && $0.id != id
            }.count
            if StoreService.shared.requiresPro(activeProtocolCount: currentActive) {
                AppLog.storeKit.warning(
                    "updateProtocolStatus(.active) blocked — would exceed free-tier cap (\(currentActive, privacy: .public) already active)"
                )
                return false
            }
        }
        protocols[index].status = status
        if status == .active {
            appendTodayEntries(for: protocols[index])
        }
        save()
        rescheduleNotificationsIfEnabled()
        return true
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
        save()
        if profile.hapticFeedbackEnabled {
            UIImpactFeedbackGenerator(style: becoming ? .light : .soft).impactOccurred()
        }
        // Live Activity reconciliation: when the user marks a dose
        // taken from the app (or undoes it), push the matching state
        // into any open lock-screen activity so the countdown stops
        // and the "Logged" badge appears before auto-dismiss.
        if becoming {
            DoseLiveActivityService.shared.markCompleted(entryId)
        } else {
            DoseLiveActivityService.shared.reconcile(entries: entries)
        }
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
            notes: notes.isEmpty ? existing.notes : notes,
            completed: true,
            actualDose: actualDose,
            actualTime: actualTime,
            injectionSite: injectionSite
        )
        save()
        if !wasCompleted, profile.hapticFeedbackEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    /// Removes a previously-logged dose — flips `completed` back to false
    /// AND clears the `actual*` capture fields so a future re-log starts
    /// from a clean slate. `toggleEntry` only flips completion, which
    /// leaves stale `actualDose`/`actualTime`/`injectionSite`/`notes`
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
        if profile.hapticFeedbackEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        DoseLiveActivityService.shared.reconcile(entries: entries)
    }

    func protocolsContaining(peptideId: UUID) -> [PeptideProtocol] {
        protocols.filter { proto in
            proto.peptides.contains { $0.id == peptideId }
        }
    }

    @discardableResult
    func addPeptide(_ peptide: Peptide, toProtocolId protocolId: UUID) -> Bool {
        guard let index = protocols.firstIndex(where: { $0.id == protocolId }) else { return false }
        if protocols[index].peptides.contains(where: { $0.id == peptide.id }) { return false }

        let existing = protocols[index]
        let updated = PeptideProtocol(
            id: existing.id,
            name: existing.name,
            peptides: existing.peptides + [peptide],
            schedule: existing.schedule,
            peptideSchedules: existing.peptideSchedules,
            cycleLengthWeeks: existing.cycleLengthWeeks,
            washoutWeeks: existing.washoutWeeks,
            startDate: existing.startDate,
            status: existing.status,
            notes: existing.notes
        )
        protocols[index] = updated

        if updated.status == .active {
            entries.removeAll { entry in
                entry.protocolId == updated.id &&
                Calendar.current.isDateInToday(entry.date) &&
                entry.peptide.id == peptide.id
            }
            entries.append(contentsOf: Self.todayEntries(for: peptide, in: updated))
        }

        save()
        rescheduleNotificationsIfEnabled()
        if profile.hapticFeedbackEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
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

        // Regenerate today's entries to reflect the new schedule. We
        // preserve any entries the user has already completed or
        // explicitly logged earlier today — re-generating without
        // this guard would silently erase logged doses, which the
        // audit (Library P0.2) flagged as real data loss for active
        // protocols too, not just paused ones.
        if updated.status == .active {
            let completedToday = entries.filter { entry in
                entry.protocolId == id
                    && Calendar.current.isDateInToday(entry.date)
                    && (entry.completed || entry.actualDose != nil || entry.notes != nil)
            }
            entries.removeAll { entry in
                entry.protocolId == id && Calendar.current.isDateInToday(entry.date)
            }
            // Append regenerated entries first, then re-insert the
            // user-logged ones. If the regenerated schedule already
            // covers the same (peptide, time) pair, the user's
            // completion wins via the dedup pass below.
            let fresh = Self.generateTodayEntries(for: updated)
            var merged = fresh
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

        save()
        rescheduleNotificationsIfEnabled()
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

        let updated = PeptideProtocol(
            id: existing.id,
            name: existing.name,
            peptides: existing.peptides,
            schedule: existing.schedule,
            peptideSchedules: overrides,
            cycleLengthWeeks: existing.cycleLengthWeeks,
            washoutWeeks: existing.washoutWeeks,
            startDate: existing.startDate,
            status: existing.status,
            notes: existing.notes,
            authorName: existing.authorName,
            authorHandle: existing.authorHandle,
            forkedFromStackId: existing.forkedFromStackId,
            createdAt: existing.createdAt
        )
        protocols[index] = updated

        // Regenerate today's entries for this protocol so the change takes effect immediately.
        entries.removeAll { entry in
            entry.protocolId == protocolId && Calendar.current.isDateInToday(entry.date)
        }
        if updated.status == .active {
            entries.append(contentsOf: Self.generateTodayEntries(for: updated))
        }

        save()
        rescheduleNotificationsIfEnabled()
        if profile.hapticFeedbackEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
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
        let calendar = Calendar.current
        let grouped = activeEntriesByDay
        let todayStart = calendar.startOfDay(for: Date())

        let todayHasCompleted = todayEntries.contains(where: \.completed)
        let startOffset = todayHasCompleted ? 0 : 1

        var streak = 0
        var consecutiveEmptyDays = 0
        for dayOffset in startOffset..<365 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: todayStart) else { break }
            let dayEntries = grouped[date] ?? []

            if dayEntries.isEmpty {
                consecutiveEmptyDays += 1
                if consecutiveEmptyDays > 2 { break }
                continue
            }

            consecutiveEmptyDays = 0
            if !dayEntries.contains(where: \.completed) { break }
            streak += 1
        }

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
        let grouped = activeEntriesByDay
        guard let earliest = grouped.keys.min() else { return 0 }
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        // Mirror currentStreak's gap-tolerance: a day with no entries
        // doesn't break the streak (up to 2 in a row), a day with at
        // least one completed entry extends it, a day with entries but
        // none completed breaks it. Without this, non-daily schedules
        // produce a `bestStreak` that's always ≤ `currentStreak`, which
        // is misleading for users on every-other-day protocols.
        var best = 0
        var current = 0
        var consecutiveEmptyDays = 0
        var day = earliest
        while day <= todayStart {
            let dayEntries = grouped[day] ?? []
            if dayEntries.isEmpty {
                consecutiveEmptyDays += 1
                if consecutiveEmptyDays > 2 {
                    current = 0
                    consecutiveEmptyDays = 0
                }
            } else if dayEntries.contains(where: \.completed) {
                consecutiveEmptyDays = 0
                current += 1
                best = max(best, current)
            } else {
                current = 0
                consecutiveEmptyDays = 0
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

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

        let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
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
    func adherence(forProtocol id: UUID) -> Double {
        let now = Date()
        let protocolEntries = entries.filter { $0.protocolId == id && $0.date <= now }
        let grouped = protocolEntries.groupedByDay
        guard !grouped.isEmpty else { return 0 }

        let dailyCompliance = grouped.map { _, dayEntries in
            let completed = dayEntries.filter(\.completed).count
            return Double(completed) / Double(dayEntries.count)
        }

        return dailyCompliance.reduce(0, +) / Double(dailyCompliance.count)
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
        let result = InsightEngine.generateInsights(from: entries, protocols: protocols).first
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

    /// Updates the calorie + macro targets surfaced on the Lifestyle tab.
    /// Pass `nil` to clear them and re-show the empty-state CTA.
    func updateNutritionTargets(_ targets: NutritionTargets?) {
        profile.nutritionTargets = targets
        save()
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
    }

    /// Weight history with at-most-one entry per calendar day.
    /// See `LifestyleDataLogic.dedupedWeightHistory` for the dedup rule
    /// (most recently logged entry within each day wins).
    var dedupedWeightHistory: [WeightEntry] {
        LifestyleDataLogic.dedupedWeightHistory(profile)
    }

    func deleteWeight(id: UUID) {
        LifestyleDataLogic.deleteWeight(from: &profile, id: id)
        save()
    }

    func logMeal(calories: Int, proteinG: Int, carbsG: Int, fatG: Int, date: Date = Date()) {
        LifestyleDataLogic.logMeal(
            into: &profile,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            date: date
        )
        save()
    }

    func unlogMeal(calories: Int, proteinG: Int, carbsG: Int, fatG: Int, date: Date = Date()) {
        LifestyleDataLogic.unlogMeal(
            from: &profile,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            date: date
        )
        save()
    }

    func logWater(oz: Int, date: Date = Date()) {
        LifestyleDataLogic.logWater(into: &profile, oz: oz, date: date)
        save()
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
    /// When `healthKitNutritionEnabled` is on, fires a background
    /// HealthKit write tagged with the entry's UUID. The HK write is
    /// fire-and-forget — failures log and disappear because they
    /// shouldn't block the in-app log. Undo removes the matching
    /// samples by metadata anchor.
    func logMealEntry(_ entry: MealEntry) {
        LifestyleDataLogic.logMealEntry(into: &profile, entry: entry)
        save()
        if profile.healthKitNutritionEnabled {
            Task { await HealthKitService.shared.writeMealEntry(entry) }
        }
    }

    /// Updates a previously logged meal entry's category. Macro values
    /// stay frozen at log time — the aggregate doesn't shift, only the
    /// per-category breakdown does. Used by `MealEntryEditorSheet` so
    /// a near-boundary auto-pick (10:55 → breakfast when the user
    /// meant lunch) can be corrected without reaching for unlog +
    /// re-log. No-op when the id isn't in history.
    func updateMealEntry(_ updated: MealEntry) {
        guard let index = profile.mealHistory.firstIndex(where: { $0.id == updated.id }) else { return }
        profile.mealHistory[index] = updated
        save()
    }

    /// Removes a meal entry by id and rolls back its contribution to
    /// the day's aggregate. Used by every review screen's Undo button
    /// once it switches to the new logging path.
    func unlogMealEntry(id: UUID) {
        let mirroredToHealthKit = profile.healthKitNutritionEnabled
        LifestyleDataLogic.unlogMealEntry(from: &profile, id: id)
        save()
        if mirroredToHealthKit {
            Task { await HealthKitService.shared.deleteSamples(forEntryID: id) }
        }
    }

    /// Flips the Apple Health write toggle. When turning ON, requests
    /// HK write permission first — if that fails (sim, denied, no
    /// HealthKit on iPad), the toggle stays off and we surface the
    /// failure via the returned Bool so the caller can show an
    /// error pill or revert the switch.
    ///
    /// Apple's privacy model doesn't tell us whether the user
    /// approved or denied; we treat "permission prompt completed
    /// without throwing" as success. The user can revoke any time in
    /// the Settings → Health pane, which is the right level of
    /// indirection for a delete-everything action.
    @discardableResult
    func setHealthKitNutritionEnabled(_ enabled: Bool) async -> Bool {
        if enabled {
            let granted = await HealthKitService.shared.requestNutritionWriteAuthorization()
            guard granted else {
                profile.healthKitNutritionEnabled = false
                save()
                return false
            }
        }
        profile.healthKitNutritionEnabled = enabled
        save()
        return true
    }

    /// Per-category breakdown for today (or any day). Used by the new
    /// `MealCategoriesCard` on the Lifestyle tab.
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
        LifestyleDataLogic.mealLoggingStreak(in: profile)
    }

    /// All-time best meal-logging streak. Surfaced on the Lifestyle
    /// tab when the user is below their personal record.
    var bestMealLoggingStreak: Int {
        LifestyleDataLogic.bestMealLoggingStreak(in: profile)
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
        LabDataLogic.deleteLabValue(from: &profile, id: id)
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

    /// Shifts every active protocol's preferred dose times by the
    /// timezone delta. Use when the user opts to translate their
    /// schedule to local clock after a flight. Also acknowledges
    /// the new timezone so the prompt won't re-fire on the next
    /// launch in the same zone. Regenerates today's entries so
    /// the new times reflect immediately on the Home + Lifestyle
    /// tabs, and re-schedules notifications via the standard save
    /// path.
    func applyTravelShift(toTimezone identifier: String, hoursDelta: Int) {
        TravelModeLogic.shiftProtocolTimes(in: &protocols, byHours: hoursDelta)
        TravelModeLogic.acknowledgeTimezoneChange(in: &profile, to: identifier)
        regenerateTodayEntries()
        save()
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
        if applied { save() }
        return applied
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
    func logRecipe(_ recipe: Recipe, category: MealCategory? = nil, at date: Date = Date()) {
        let totals = RecipeDataLogic.totals(
            for: recipe,
            customFoods: profile.customFoods
        )
        let chosenCategory = category ?? MealCategory.auto(for: date)
        let entry = MealEntry(
            loggable: totals,
            name: recipe.name,
            category: chosenCategory,
            source: .custom,
            sourceID: nil,
            date: date
        )
        logMealEntry(entry)
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

    // MARK: - Vial inventory (derived)

    /// Default doses per vial when the user hasn't told us otherwise.
    /// Picked because most short-acting research peptides come as 5 mg
    /// vials reconstituted to deliver ~20–30 doses, and the modulo wrap
    /// reads as a believable "vial swap" cadence in the Home shelf.
    static let defaultDosesPerVial = 30

    /// Liquid-fill fraction for a compound's vial. Math lives in
    /// `VialInventoryLogic.liquidLevel(for:in:dosesPerVial:)` so it's
    /// unit-testable in isolation; this method only forwards.
    func liquidLevel(for peptide: Peptide) -> Double {
        VialInventoryLogic.liquidLevel(
            for: peptide,
            in: entries,
            dosesPerVial: Self.defaultDosesPerVial
        )
    }

    func logWorkout(_ entry: WorkoutEntry) {
        LifestyleDataLogic.logWorkout(into: &profile, entry: entry)
        save()
    }

    func deleteWorkout(id: UUID) {
        LifestyleDataLogic.deleteWorkout(from: &profile, id: id)
        save()
    }

    /// (count, totalMinutes) for workout sessions logged on `date`'s
    /// calendar day.
    func workoutSummary(for date: Date = Date()) -> (count: Int, minutes: Int) {
        LifestyleDataLogic.workoutSummary(of: profile, for: date)
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
    /// only succeeds after the user has actually granted at least
    /// one HealthKit type — previously we'd flip the bool to true
    /// regardless, then PeptideApp's task fired
    /// startBackgroundDelivery against permissionless observer
    /// queries, and downstream UI showed "connected" with empty
    /// cards (audit Biology H9). Caller can `await` the result and
    /// surface a permissions prompt when this returns false.
    @discardableResult
    func toggleHealthConnection() async -> Bool {
        if profile.healthConnected {
            profile.healthConnected = false
            save()
            return true
        }
        let granted = await HealthKitService.shared.requestAuthorization()
        guard granted else {
            AppLog.healthKit.warning("toggleHealthConnection blocked — no HealthKit grant")
            return false
        }
        profile.healthConnected = true
        save()
        return true
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
    }

    func updateHabit(_ habit: Habit) {
        guard let idx = profile.habits.firstIndex(where: { $0.id == habit.id }) else { return }
        profile.habits[idx] = habit
        save()
    }

    /// Soft-delete via the `archived` flag so the history isn't
    /// thrown away the moment the user removes a habit. Hard delete
    /// is `purgeArchivedHabits()` from settings if we ever expose it.
    func archiveHabit(id: UUID) {
        guard let idx = profile.habits.firstIndex(where: { $0.id == id }) else { return }
        profile.habits[idx].archived = true
        save()
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
    }

    /// Set the exact value for a given day. Use for countable habits
    /// where the user wants to type "6 glasses" rather than tap +1
    /// six times. Value 0 = uncompleted (removes the entry to keep
    /// the storage compact).
    func setHabitEntry(habitId: UUID, date: Date, value: Int) {
        let day = Calendar.current.startOfDay(for: date)
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
    }

    /// One-tap adoption of an onboarding-recommended starter stack. Creates a
    /// gentle 8-week protocol on a 5-days-on / 2-days-off cadence, mornings
    /// only — the most forgiving default. The user can edit it immediately.
    @discardableResult
    func adoptStarterProtocol(
        peptides: [Peptide],
        name: String = "Starter Stack"
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
            notes: "Generated from your onboarding goals. Review and adjust before starting."
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

    private func rescheduleNotificationsIfEnabled() {
        guard profile.doseRemindersEnabled else { return }
        NotificationService.shared.scheduleNotifications(for: activeProtocols)
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

    private func performSaveNow() {
        // Ephemeral mode (screenshot capture) — never write to disk.
        // The demo state lives entirely in memory and dies when the
        // user flips the toggle off + reloadFromDisk restores the
        // real data.
        guard !isEphemeral else { return }
        repo.saveProtocols(protocols)
        repo.saveEntries(entries)
        repo.saveProfile(profile)
        updateWidgetData()
        updateWatchData()
    }

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
        self.profile = newProfile
        self.protocols = newProtocols
        self.entries = newEntries
        cacheVersion &+= 1
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
    /// the same numbers the Lifestyle tab shows.
    private func updateWidgetData() {
        let data = WidgetSnapshotBuilder.build(
            today: todayEntries,
            next: nextDose,
            consumption: LifestyleDataLogic.consumption(in: profile, for: Date()),
            targets: profile.nutritionTargets,
            breakdown: LifestyleDataLogic.mealsByCategory(in: profile, for: Date())
        )
        PersistenceService.shared.updateWidgetData(data)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Pushes a snapshot through `WatchSyncService`. Math (compliance
    /// fraction, lifetime total) is delegated to `EntryAnalytics` so the
    /// definitions are shared with any future watch / widget / share-card
    /// surface that needs the same numbers.
    private func updateWatchData() {
        // Surface the same stats the Stats page on the watch reads —
        // streak, week compliance, total logged. The watch carries
        // these forward as optionals so an older phone build (without
        // these fields in the JSON) still decodes cleanly.
        WatchSyncService.shared.updateWatchData(
            entries: entries,
            protocols: protocols,
            currentStreak: currentStreak,
            weeklyCompliance: EntryAnalytics.weeklyComplianceFraction(in: entries),
            totalDosesLogged: EntryAnalytics.totalDosesLogged(in: entries),
            nutrition: nutritionSnapshotForWatch()
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


    private func scheduleAchievementCheck() {
        guard !achievementCheckPending else { return }
        achievementCheckPending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.achievementCheckPending = false
            AchievementService.shared.checkAchievements(
                totalDoses: self.totalDoses,
                currentStreak: self.currentStreak,
                bestStreak: self.bestStreak,
                protocolCount: self.protocols.count,
                daysLogged: self.totalDaysLogged
            )
            // Lifestyle milestones run on the same hook so the
            // achievement toast pipeline doesn't fire twice for
            // unrelated mutations. The two `checkAchievements`
            // calls each manage their own `latestUnlock` — only
            // the second one's value survives, but in practice
            // the two domains rarely cross a threshold on the
            // same mutation.
            AchievementService.shared.checkLifestyleAchievements(
                mealsLogged: self.profile.mealHistory.count,
                mealStreak: self.mealLoggingStreak,
                labsLogged: self.profile.labHistory.count,
                labPanelCount: Set(self.profile.labHistory.map(\.panel)).count,
                recipesCount: self.profile.recipes.count,
                checkInsLogged: self.profile.outcomeHistory.count
            )
        }
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
        regenerateTodayEntries()
    }

    /// Re-pulls protocols / entries / profile from the repository — used by
    /// the Protocols list's pull-to-refresh so a CloudKit sync from another
    /// device shows up without an app relaunch. Falls back to the existing
    /// in-memory state if the repo returns nil for that resource.
    func reloadFromDisk() {
        protocols = repo.loadProtocols()
        entries = repo.loadEntries()
        if let saved = repo.loadProfile() { profile = saved }
        regenerateTodayEntries()
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
    nonisolated(unsafe) private static let timeStringParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func todayEntries(for peptide: Peptide, in proto: PeptideProtocol) -> [ProtocolEntry] {
        guard proto.status == .active else { return [] }

        let schedule = proto.schedule(for: peptide.id)
        let calendar = Calendar.current
        guard schedule.isActive(on: Date(), calendar: calendar) else { return [] }

        return schedule.preferredTimes.compactMap { timeString in
            guard let time = timeStringParser.date(from: timeString) else { return nil }
            let hour = calendar.component(.hour, from: time)
            let minute = calendar.component(.minute, from: time)
            let entryDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
            return ProtocolEntry(
                id: UUID(),
                protocolId: proto.id,
                peptide: peptide,
                date: entryDate,
                dose: schedule.resolvedDose(for: peptide),
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
