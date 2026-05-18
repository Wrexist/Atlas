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

    var daysDescription: String {
        if isInterval, let n = intervalDays {
            return n == 1 ? "Every day" : "Every \(n) days"
        }
        let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let validDays = daysOfWeek.filter { (1...7).contains($0) }
        if validDays.count == 7 { return "Every day" }
        return validDays.sorted().map { dayNames[$0 - 1] }.joined(separator: ", ")
    }

    var compactDaysDescription: String {
        if isInterval, let n = intervalDays {
            return n == 1 ? "Daily" : "Every \(n)d"
        }
        let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let validDays = daysOfWeek.filter { (1...7).contains($0) }.sorted()
        if validDays.count == 7 { return "Daily" }
        return validDays.map { dayNames[$0 - 1] }.joined(separator: ", ")
    }

    var summary: String {
        "\(compactDaysDescription) · \(timesPerDay)x"
    }

    /// Returns the dose for an entry, preferring the custom override and
    /// falling back to the peptide's high end of its default dosage range.
    /// Whitespace- or newline-only overrides are treated as empty so legacy
    /// data with stray whitespace doesn't surface as a custom dose.
    func resolvedDose(for peptide: Peptide) -> String {
        if let customDose {
            let normalized = customDose.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty { return normalized }
        }
        return peptide.dosageRange
            .components(separatedBy: "-")
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? peptide.dosageRange
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
    let cycleLengthWeeks: Int
    /// Wash-out duration between repeated cycles, in weeks. `0`
    /// (default) means the protocol runs a single cycle and ends —
    /// no wash-out, no repeat. Non-zero means an alternating on/off
    /// pattern: `cycleLengthWeeks` on, `washoutWeeks` off, repeat.
    /// Lets the cycle-phase engine compute whether the user is
    /// currently in an "on" phase or a "wash-out" phase without
    /// inventing the data after the fact.
    let washoutWeeks: Int
    let startDate: Date
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

    /// Returns the override schedule for a peptide, falling back to the protocol default.
    func schedule(for peptideId: UUID) -> ProtocolSchedule {
        peptideSchedules[peptideId] ?? schedule
    }

    func hasCustomSchedule(for peptideId: UUID) -> Bool {
        peptideSchedules[peptideId] != nil
    }

    var endDate: Date {
        Calendar.current.date(byAdding: .weekOfYear, value: cycleLengthWeeks, to: startDate) ?? startDate
    }

    var cycleProgress: Double {
        let total = endDate.timeIntervalSince(startDate)
        let elapsed = Date().timeIntervalSince(startDate)
        guard total > 0 else { return 0 }
        return min(max(elapsed / total, 0), 1)
    }

    var daysRemaining: Int {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0
        return max(days, 0)
    }

    var weekNumber: Int {
        let weeks = Calendar.current.dateComponents([.weekOfYear], from: startDate, to: Date()).weekOfYear ?? 0
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
        let weeks = Calendar.current.dateComponents([.weekOfYear], from: startDate, to: Date()).weekOfYear ?? 0
        return max(1, (weeks / totalCycleWeeks) + 1)
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
