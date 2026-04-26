import Foundation

struct ProtocolSchedule: Hashable, Codable {
    let daysOfWeek: [Int]  // 1=Mon, 7=Sun
    let timesPerDay: Int
    let preferredTimes: [String]

    var daysDescription: String {
        let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let validDays = daysOfWeek.filter { (1...7).contains($0) }
        if validDays.count == 7 { return "Every day" }
        return validDays.sorted().map { dayNames[$0 - 1] }.joined(separator: ", ")
    }

    var compactDaysDescription: String {
        let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let validDays = daysOfWeek.filter { (1...7).contains($0) }.sorted()
        if validDays.count == 7 { return "Daily" }
        return validDays.map { dayNames[$0 - 1] }.joined(separator: ", ")
    }

    var summary: String {
        "\(compactDaysDescription) · \(timesPerDay)x"
    }
}

struct PeptideProtocol: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let peptides: [Peptide]
    let schedule: ProtocolSchedule
    let peptideSchedules: [UUID: ProtocolSchedule]
    let cycleLengthWeeks: Int
    let startDate: Date
    var status: ProtocolStatus
    let notes: String

    init(
        id: UUID,
        name: String,
        peptides: [Peptide],
        schedule: ProtocolSchedule,
        peptideSchedules: [UUID: ProtocolSchedule] = [:],
        cycleLengthWeeks: Int,
        startDate: Date,
        status: ProtocolStatus,
        notes: String
    ) {
        self.id = id
        self.name = name
        self.peptides = peptides
        self.schedule = schedule
        self.peptideSchedules = peptideSchedules
        self.cycleLengthWeeks = cycleLengthWeeks
        self.startDate = startDate
        self.status = status
        self.notes = notes
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
        return max(1, min(weeks + 1, cycleLengthWeeks))
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
        case cycleLengthWeeks, startDate, status, notes
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
        self.startDate = try c.decode(Date.self, forKey: .startDate)
        self.status = try c.decode(ProtocolStatus.self, forKey: .status)
        self.notes = try c.decode(String.self, forKey: .notes)
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
        try c.encode(startDate, forKey: .startDate)
        try c.encode(status, forKey: .status)
        try c.encode(notes, forKey: .notes)
    }
}
