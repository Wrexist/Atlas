import Foundation

@MainActor
protocol DataServiceProtocol {
    // Protocol management
    var protocols: [PeptideProtocol] { get }
    var activeProtocols: [PeptideProtocol] { get }
    var pausedProtocols: [PeptideProtocol] { get }
    var completedProtocols: [PeptideProtocol] { get }
    func addProtocol(_ protocol: PeptideProtocol)
    func deleteProtocol(id: UUID)
    func updateProtocolStatus(id: UUID, to status: ProtocolStatus)

    // Entry management
    var entries: [ProtocolEntry] { get }
    var todayEntries: [ProtocolEntry] { get }
    func toggleEntry(_ entryId: UUID)
    func logDose(entryId: UUID, actualDose: String?, actualTime: Date?, injectionSite: String?, notes: String)
    func entriesFor(protocolId: UUID, days: Int) -> [ProtocolEntry]

    // Protocol editing
    func updateProtocol(id: UUID, name: String, peptides: [Peptide], schedule: ProtocolSchedule, peptideSchedules: [UUID: ProtocolSchedule], cycleLengthWeeks: Int, washoutWeeks: Int, notes: String)
    func setPeptideSchedule(protocolId: UUID, peptideId: UUID, schedule: ProtocolSchedule?)

    // Peptide database
    var peptideDatabase: [Peptide] { get }

    // Stats
    var currentStreak: Int { get }
    var totalDaysLogged: Int { get }
    var totalDoses: Int { get }
    var bestStreak: Int { get }
    var averageCompliance: Double { get }
    func complianceTrend(for range: Int) -> Double
    var nextDose: ProtocolEntry? { get }

    // Profile
    var profile: UserProfile { get }
    func updateGoals(_ goals: Set<String>)
    func toggleHealthConnection()
}
