import Foundation

struct ProtocolSchedule: Hashable, Codable, Sendable {
    let daysOfWeek: [Int]  // 1=Mon, 7=Sun
    let timesPerDay: Int
    let preferredTimes: [String]
    /// Optional custom dose override (e.g. "300 mcg"). When nil, the peptide's
    /// default `dosageRange` is used. Only meaningful for per-peptide overrides.
    let customDose: String?
    /// When non-nil and >= 1, the schedule fires every N days starting from
    /// `intervalAnchor`, and `daysOfWeek` is ignored. Use `isInterval` to
    /// check the active mode rather than reading this directly.
    let intervalDays: Int?
    /// First active date for the interval cadence. Falls back to today if nil.
    let intervalAnchor: Date?

    init(
        daysOfWeek: [Int],
        timesPerDay: Int,
        preferredTimes: [String],
        customDose: String? = nil,
        intervalDays: Int? = nil,
        intervalAnchor: Date? = nil
    ) {
        self.daysOfWeek = daysOfWeek
        self.timesPerDay = timesPerDay
        self.preferredTimes = preferredTimes
        self.customDose = customDose
        self.intervalDays = intervalDays
        self.intervalAnchor = intervalAnchor
    }

    /// True when the schedule is in "every N days" mode. Callers should branch
    /// on this rather than peeking at `intervalDays` directly so they don't
    /// accidentally treat 0 / negative as a valid interval.
    var isInterval: Bool { (intervalDays ?? 0) >= 1 }

    /// Returns true if this schedule is active on `date`, honoring whichever
    /// cadence (weekly day-of-week or every-N-days) is configured.
    func isActive(on date: Date, calendar: Calendar = .current) -> Bool {
        if isInterval, let n = intervalDays, n >= 1 {
            let anchor = intervalAnchor ?? date
            let anchorDay = calendar.startOfDay(for: anchor)
            let target = calendar.startOfDay(for: date)
            let diff = calendar.dateComponents([.day], from: anchorDay, to: target).day ?? 0
            // Match days on or after the anchor where the offset is divisible
            // by N. Days before the anchor are off-schedule (we don't
            // backfill into the past from a future-dated anchor).
            return diff >= 0 && diff % n == 0
        }
        let weekday = calendar.component(.weekday, from: date)
        let isoDay = weekday == 1 ? 7 : weekday - 1
        return daysOfWeek.contains(isoDay)
    }

    /// `isActive(on:)`, except an interval schedule with no stored anchor
    /// (library imports) counts from the protocol's start instead of
    /// matching every day.
    func isActive(on date: Date, protocolStart: Date, calendar: Calendar = .current) -> Bool {
        guard isInterval, intervalAnchor == nil else {
            return isActive(on: date, calendar: calendar)
        }
        let anchored = ProtocolSchedule(
            daysOfWeek: daysOfWeek,
            timesPerDay: timesPerDay,
            preferredTimes: preferredTimes,
            customDose: customDose,
            intervalDays: intervalDays,
            intervalAnchor: protocolStart
        )
        return anchored.isActive(on: date, calendar: calendar)
    }

    /// `preferredTimes` are stored as en_US_POSIX "h:mm a" keys; this
    /// renders one in the user's own clock format ("08:00" on a 24-hour
    /// device). Unparseable keys pass through unchanged.
    static func displayTime(_ storageKey: String) -> String {
        guard let date = storageTimeParser.date(from: storageKey) else { return storageKey }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private static let storageTimeParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var daysDescription: String {
        if isInterval, let n = intervalDays {
            return n == 1 ? String(localized: "Every day") : String(localized: "Every \(n) days")
        }
        let validDays = daysOfWeek.filter { (1...7).contains($0) }
        if validDays.count == 7 { return String(localized: "Every day") }
        return Self.dayNames(validDays)
    }

    var compactDaysDescription: String {
        if isInterval, let n = intervalDays {
            return n == 1 ? String(localized: "Daily") : String(localized: "Every \(n)d")
        }
        let validDays = daysOfWeek.filter { (1...7).contains($0) }
        if validDays.count == 7 { return String(localized: "Daily") }
        return Self.dayNames(validDays)
    }

    /// Localised short names for ISO weekdays (1 = Mon … 7 = Sun), in
    /// Monday-first order. `shortWeekdaySymbols` starts at Sunday.
    private static func dayNames(_ isoDays: [Int], calendar: Calendar = .current) -> String {
        let symbols = calendar.shortWeekdaySymbols
        return isoDays.sorted().map { symbols[$0 % 7] }.joined(separator: ", ")
    }

    var summary: String {
        "\(compactDaysDescription) · \(timesPerDay)x"
    }

    /// The user's own dose, or empty when they haven't set one. Never
    /// derived from the database's free-text research range: that prose
    /// doesn't parse into a dose, and presenting a reference figure as
    /// the user's dose breaks Guideline 1.4.1. Whitespace-only overrides
    /// from legacy data count as unset.
    var resolvedDose: String {
        customDose?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Codable (backwards-compatible: customDose / interval are optional)

    private enum CodingKeys: String, CodingKey {
        case daysOfWeek, timesPerDay, preferredTimes, customDose
        case intervalDays, intervalAnchor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.daysOfWeek = try c.decode([Int].self, forKey: .daysOfWeek)
        self.timesPerDay = try c.decode(Int.self, forKey: .timesPerDay)
        self.preferredTimes = try c.decode([String].self, forKey: .preferredTimes)
        self.customDose = try c.decodeIfPresent(String.self, forKey: .customDose)
        self.intervalDays = try c.decodeIfPresent(Int.self, forKey: .intervalDays)
        self.intervalAnchor = try c.decodeIfPresent(Date.self, forKey: .intervalAnchor)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(daysOfWeek, forKey: .daysOfWeek)
        try c.encode(timesPerDay, forKey: .timesPerDay)
        try c.encode(preferredTimes, forKey: .preferredTimes)
        if let customDose {
            let normalized = customDose.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                try c.encode(normalized, forKey: .customDose)
            }
        }
        if let intervalDays, intervalDays >= 1 {
            try c.encode(intervalDays, forKey: .intervalDays)
            try c.encodeIfPresent(intervalAnchor, forKey: .intervalAnchor)
        }
    }
}

struct PeptideProtocol: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let name: String
    let peptides: [Peptide]
    let schedule: ProtocolSchedule
    let peptideSchedules: [UUID: ProtocolSchedule]
    var cycleLengthWeeks: Int
    /// Wash-out duration between repeated cycles, in weeks. `0`
    /// (default) means the protocol runs a single cycle and ends —
    /// no wash-out, no repeat. Non-zero means an alternating on/off
    /// pattern: `cycleLengthWeeks` on, `washoutWeeks` off, repeat.
    /// Lets the cycle-phase engine compute whether the user is
    /// currently in an "on" phase or a "wash-out" phase without
    /// inventing the data after the fact.
    let washoutWeeks: Int
    var startDate: Date
    var status: ProtocolStatus
    let notes: String
    let authorName: String?
    let authorHandle: String?
    let forkedFromStackId: UUID?
    let createdAt: Date

    init(
        id: UUID,
        name: String,
        peptides: [Peptide],
        schedule: ProtocolSchedule,
        peptideSchedules: [UUID: ProtocolSchedule] = [:],
        cycleLengthWeeks: Int,
        washoutWeeks: Int = 0,
        startDate: Date,
        status: ProtocolStatus,
        notes: String,
        authorName: String? = nil,
        authorHandle: String? = nil,
        forkedFromStackId: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.peptides = peptides
        self.schedule = schedule
        self.peptideSchedules = peptideSchedules
        self.cycleLengthWeeks = cycleLengthWeeks
        self.washoutWeeks = washoutWeeks
        self.startDate = startDate
        self.status = status
        self.notes = notes
        self.authorName = authorName
        self.authorHandle = authorHandle
        self.forkedFromStackId = forkedFromStackId
        self.createdAt = createdAt
    }

    /// A copy with its dosing content replaced. Identity, attribution,
    /// cycle and status carry over, so a rebuild can't silently reset
    /// the template link or creation date.
    func with(
        peptides: [Peptide]? = nil,
        schedule: ProtocolSchedule? = nil,
        peptideSchedules: [UUID: ProtocolSchedule]? = nil
    ) -> PeptideProtocol {
        PeptideProtocol(
            id: id,
            name: name,
            peptides: peptides ?? self.peptides,
            schedule: schedule ?? self.schedule,
            peptideSchedules: peptideSchedules ?? self.peptideSchedules,
            cycleLengthWeeks: cycleLengthWeeks,
            washoutWeeks: washoutWeeks,
            startDate: startDate,
            status: status,
            notes: notes,
            authorName: authorName,
            authorHandle: authorHandle,
            forkedFromStackId: forkedFromStackId,
            createdAt: createdAt
        )
    }

    /// Returns the override schedule for a peptide, falling back to the protocol default.
    func schedule(for peptideId: UUID) -> ProtocolSchedule {
        peptideSchedules[peptideId] ?? schedule
    }

    func hasCustomSchedule(for peptideId: UUID) -> Bool {
        peptideSchedules[peptideId] != nil
    }

    /// Completed doses ÷ doses due over the last `days` calendar days,
    /// today included. Entries are only generated on days the app is
    /// opened, so past days take their due count from the schedule — a
    /// day the app never saw counts as missed rather than vanishing.
    /// Wash-out days and days past the cycle's end have nothing due.
    /// Today only counts doses already due or already taken. Nil when
    /// nothing was due in the window.
    func adherence(
        entries: [ProtocolEntry],
        days: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double? {
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return nil }
        let firstDay = max(windowStart, calendar.startOfDay(for: startDate))
        let windowEntries = entries.filter { $0.protocolId == id && $0.date >= firstDay }

        var due = 0
        var completed = 0
        var day = firstDay
        while day < today {
            let dayEntries = windowEntries.filter { calendar.isDate($0.date, inSameDayAs: day) }
            let scheduled = status == .active && CyclePhaseEngine.isOnCycle(day, protocol: self, calendar: calendar)
                ? scheduledDoseCount(on: day, calendar: calendar)
                : 0
            due += max(scheduled, dayEntries.count)
            completed += dayEntries.filter(\.completed).count
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        let todayEntries = windowEntries.filter {
            calendar.isDate($0.date, inSameDayAs: today) && ($0.completed || $0.date <= now)
        }
        due += todayEntries.count
        completed += todayEntries.filter(\.completed).count

        guard due > 0 else { return nil }
        return Double(completed) / Double(due)
    }

    /// Doses the schedule puts on `day`, one per preferred time per
    /// peptide — the same shape the app generates entries in.
    private func scheduledDoseCount(on day: Date, calendar: Calendar) -> Int {
        peptides.reduce(0) { total, peptide in
            let peptideSchedule = schedule(for: peptide.id)
            guard peptideSchedule.isActive(on: day, protocolStart: startDate, calendar: calendar) else { return total }
            return total + peptideSchedule.preferredTimes.count
        }
    }

    /// End of the cycle the user is in now. Matches `cycleEndDay` for
    /// the first cycle; a wash-out protocol in a later cycle ends that
    /// cycle instead, so the card's "days left" and progress agree with
    /// its "Week N" (which wraps per cycle).
    var endDate: Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: safeCycleLengthWeeks * 7, to: currentCycleStartDay)
            ?? currentCycleStartDay
    }

    /// Start of day of the current on-phase. Only wash-out protocols
    /// repeat; a single-cycle protocol always measures from `startDate`.
    var currentCycleStartDay: Date {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: startDate)
        guard washoutWeeks > 0 else { return dayStart }
        let cycleDays = (safeCycleLengthWeeks + washoutWeeks) * 7
        return cal.date(byAdding: .day, value: (cycleNumber - 1) * cycleDays, to: dayStart) ?? dayStart
    }

    /// Canonical "cycle is over" boundary used by `CycleCompletionService`:
    /// the end of the first cycle. Normalised to `startOfDay(of: startDate)`
    /// so a protocol created at 11 PM doesn't drift its end-of-cycle
    /// across midnight relative to `endDate`. Uses `safeCycleLengthWeeks`
    /// to floor at 1 week.
    var cycleEndDay: Date {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: startDate)
        return cal.date(byAdding: .day, value: safeCycleLengthWeeks * 7, to: dayStart) ?? dayStart
    }

    /// Whole 7-day periods elapsed since `startDate`, using day-delta
    /// math. `weekOfYear` counts calendar-week boundaries crossed — a
    /// Friday start ticks to "week 2" after only 2 days — so it's
    /// wrong for cycle math. Consistent with `CyclePhaseEngine`.
    private var elapsedWeeksSinceStart: Int {
        let cal = Calendar.current
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: startDate),
            to: cal.startOfDay(for: Date())
        ).day ?? 0
        return max(0, days) / 7
    }

    var cycleProgress: Double {
        // Normalize to start-of-day on both ends: `endDate` is already
        // day-aligned, so measuring elapsed/total from the raw
        // startDate + current time made a protocol started at 11pm read
        // ~95% on its final day until midnight.
        let cal = Calendar.current
        let start = currentCycleStartDay
        let total = endDate.timeIntervalSince(start)
        let elapsed = cal.startOfDay(for: Date()).timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(max(elapsed / total, 0), 1)
    }

    /// Whole calendar days to `endDate`. Measured from today's start of
    /// day like `cycleProgress`: from `Date()` the partial day truncated
    /// and read one short for most of every day.
    var daysRemaining: Int {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: endDate).day ?? 0
        return max(days, 0)
    }

    var weekNumber: Int {
        let weeks = elapsedWeeksSinceStart
        let totalCycleWeeks = cycleLengthWeeks + washoutWeeks
        guard cycleLengthWeeks > 0 else { return 1 }
        if totalCycleWeeks > 0 {
            // Wrap into the current cycle so a user partway through a
            // second cycle reads "Week 2" of the new cycle rather than
            // staying clamped at the first cycle's final week. The
            // cycle index itself is on `cycleNumber`.
            let weekInCycle = (weeks % totalCycleWeeks) + 1
            return max(1, min(weekInCycle, cycleLengthWeeks))
        }
        return max(1, min(weeks + 1, cycleLengthWeeks))
    }

    /// Which cycle the user is currently in, 1-indexed. Increments
    /// every `cycleLengthWeeks + washoutWeeks` weeks since `startDate`,
    /// so an 8-on / 4-off protocol on its 13th calendar week reads as
    /// "Cycle 2 · Week 1" (audit Library P2.14). Returns 1 for
    /// protocols without a defined cycle length.
    var cycleNumber: Int {
        guard cycleLengthWeeks > 0 else { return 1 }
        let totalCycleWeeks = cycleLengthWeeks + washoutWeeks
        guard totalCycleWeeks > 0 else { return 1 }
        let weeks = elapsedWeeksSinceStart
        return max(1, (weeks / totalCycleWeeks) + 1)
    }

    /// Floor for `cycleLengthWeeks`. The raw value can be 0 on
    /// malformed import / migration; clamping to 1 here gives the
    /// engines (`CyclePhaseEngine`, `SmartCyclePlanner`,
    /// `DoseDayMap`, `CycleBands`, `CycleCardModel`) a single
    /// source of truth so they can't silently disagree if one site
    /// is later changed to a different floor. Use everywhere the
    /// raw `cycleLengthWeeks` is multiplied or divided.
    var safeCycleLengthWeeks: Int {
        max(1, cycleLengthWeeks)
    }

    static func == (lhs: PeptideProtocol, rhs: PeptideProtocol) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Codable (backwards-compatible: peptideSchedules is optional)

    private enum CodingKeys: String, CodingKey {
        case id, name, peptides, schedule, peptideSchedules
        case cycleLengthWeeks, washoutWeeks, startDate, status, notes
        case authorName, authorHandle, forkedFromStackId, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.peptides = try c.decode([Peptide].self, forKey: .peptides)
        self.schedule = try c.decode(ProtocolSchedule.self, forKey: .schedule)
        // Older saves: stored as [String: ProtocolSchedule] with UUID strings as keys.
        if let raw = try c.decodeIfPresent([String: ProtocolSchedule].self, forKey: .peptideSchedules) {
            self.peptideSchedules = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
                UUID(uuidString: key).map { ($0, value) }
            })
        } else {
            self.peptideSchedules = [:]
        }
        self.cycleLengthWeeks = try c.decode(Int.self, forKey: .cycleLengthWeeks)
        // `washoutWeeks` is new — decode-if-present so protocols
        // persisted before this shipped still decode (they default
        // to `0`, which preserves the old "single-cycle, no wash-out"
        // behaviour exactly).
        self.washoutWeeks = try c.decodeIfPresent(Int.self, forKey: .washoutWeeks) ?? 0
        self.startDate = try c.decode(Date.self, forKey: .startDate)
        self.status = try c.decode(ProtocolStatus.self, forKey: .status)
        self.notes = try c.decode(String.self, forKey: .notes)
        self.authorName = try c.decodeIfPresent(String.self, forKey: .authorName)
        self.authorHandle = try c.decodeIfPresent(String.self, forKey: .authorHandle)
        self.forkedFromStackId = try c.decodeIfPresent(UUID.self, forKey: .forkedFromStackId)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(peptides, forKey: .peptides)
        try c.encode(schedule, forKey: .schedule)
        if !peptideSchedules.isEmpty {
            let raw = Dictionary(uniqueKeysWithValues: peptideSchedules.map { ($0.key.uuidString, $0.value) })
            try c.encode(raw, forKey: .peptideSchedules)
        }
        try c.encode(cycleLengthWeeks, forKey: .cycleLengthWeeks)
        // Skip encoding when zero so the on-disk shape stays
        // compact for the common case (no wash-out configured).
        if washoutWeeks > 0 {
            try c.encode(washoutWeeks, forKey: .washoutWeeks)
        }
        try c.encode(startDate, forKey: .startDate)
        try c.encode(status, forKey: .status)
        try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(authorName, forKey: .authorName)
        try c.encodeIfPresent(authorHandle, forKey: .authorHandle)
        try c.encodeIfPresent(forkedFromStackId, forKey: .forkedFromStackId)
        try c.encode(createdAt, forKey: .createdAt)
    }
}
