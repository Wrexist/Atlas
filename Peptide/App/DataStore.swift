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
    /// AnalyticsView complianceData / weeklyDoseData) share one O(n) group
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
    }

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

    func updateProtocolStatus(id: UUID, to status: ProtocolStatus) {
        guard let index = protocols.firstIndex(where: { $0.id == id }) else { return }
        protocols[index].status = status
        if status == .active {
            appendTodayEntries(for: protocols[index])
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
            startDate: existing.startDate,
            status: existing.status,
            notes: notes,
            authorName: existing.authorName,
            authorHandle: existing.authorHandle,
            forkedFromStackId: existing.forkedFromStackId,
            createdAt: existing.createdAt
        )
        protocols[index] = updated

        // Regenerate today's entries to reflect the new schedule — but
        // only when the protocol is active. For paused / completed
        // protocols, deleting today's entries would discard any doses
        // the user already logged earlier today against that protocol,
        // which is real data loss.
        if updated.status == .active {
            entries.removeAll { entry in
                entry.protocolId == id && Calendar.current.isDateInToday(entry.date)
            }
            entries.append(contentsOf: Self.generateTodayEntries(for: updated))
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
    /// must already exist in `profile.goals` — otherwise the call is ignored.
    func setPrimaryGoal(_ goal: String?) {
        if let goal, !profile.goals.contains(goal) { return }
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
    /// Pulls the matching Spotlight item synchronously so a search
    /// the moment after delete can't surface a dangling result.
    func deleteCustomFood(id: UUID) {
        profile.customFoods.removeAll { $0.id == id }
        profile.favoriteFoodIDs.remove("custom:\(id.uuidString)")
        save()
        Task { await FoodSpotlightService.shared.removeCustomFood(id: id) }
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
    /// off `BarcodeProductCache` so they index with their full name +
    /// brand + thumbnail. Failures log but don't propagate — Spotlight
    /// is a nice-to-have surface, never a critical-path dependency.
    private func reindexFoodLibraryInBackground() {
        let snapshot = profile
        let offIDs = profile.favoriteFoodIDs.filter { !$0.hasPrefix("custom:") }
        Task {
            var cached: [ScannedProduct] = []
            cached.reserveCapacity(offIDs.count)
            for id in offIDs {
                if let product = await BarcodeProductCache.shared.read(barcode: id) {
                    cached.append(product)
                }
            }
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

    func toggleHealthConnection() {
        profile.healthConnected.toggle()
        save()
    }

    /// Atomically updates the user-customizable identity fields shown on the
    /// profile customization sheet. Whitespace is trimmed; `bio` collapses
    /// empty strings to "" so the profile JSON stays compact.
    func updateProfileIdentity(name: String, bio: String) {
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.bio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    func updateAvatarImageData(_ data: Data?) {
        profile.avatarImageData = data
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
        repo.saveProtocols(protocols)
        repo.saveEntries(entries)
        repo.saveProfile(profile)
        updateWidgetData()
        updateWatchData()
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
            totalDosesLogged: EntryAnalytics.totalDosesLogged(in: entries)
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
