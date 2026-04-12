import Foundation

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

enum MockEntries {
    static func generateEntries(for protocol_: PeptideProtocol, days: Int = 30) -> [ProtocolEntry] {
        var entries: [ProtocolEntry] = []
        let calendar = Calendar.current
        var rng = SeededGenerator(seed: UInt64(bitPattern: Int64(protocol_.name.hashValue &+ days)))
        let startOfProtocol = calendar.startOfDay(for: protocol_.startDate)
        let endOfProtocol = calendar.startOfDay(for: protocol_.endDate)

        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let dayStart = calendar.startOfDay(for: date)

            // Only generate entries within the protocol's active date range
            guard dayStart >= startOfProtocol && dayStart <= endOfProtocol else { continue }

            let dayOfWeek = calendar.component(.weekday, from: date)
            let isoDayOfWeek = dayOfWeek == 1 ? 7 : dayOfWeek - 1

            guard protocol_.schedule.daysOfWeek.contains(isoDayOfWeek) else { continue }

            for peptide in protocol_.peptides {
                let completed = Double.random(in: 0...1, using: &rng) < 0.82
                let entry = ProtocolEntry(
                    id: UUID(),
                    protocolId: protocol_.id,
                    peptide: peptide,
                    date: date,
                    dose: peptide.dosageRange.components(separatedBy: "-").last ?? peptide.dosageRange,
                    notes: "",
                    completed: completed
                )
                entries.append(entry)
            }
        }

        return entries.sorted { $0.date > $1.date }
    }

    static var allEntries: [ProtocolEntry] {
        MockProtocols.all.flatMap { generateEntries(for: $0) }
    }

    static func todayEntries() -> [ProtocolEntry] {
        let calendar = Calendar.current
        return [
            ProtocolEntry(
                id: UUID(),
                protocolId: MockProtocols.recoveryStack.id,
                peptide: MockPeptides.bpc157,
                date: calendar.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date(),
                dose: "250 mcg",
                notes: "",
                completed: true
            ),
            ProtocolEntry(
                id: UUID(),
                protocolId: MockProtocols.recoveryStack.id,
                peptide: MockPeptides.ghkCu,
                date: calendar.date(bySettingHour: 8, minute: 5, second: 0, of: Date()) ?? Date(),
                dose: "1 mg",
                notes: "",
                completed: true
            ),
            ProtocolEntry(
                id: UUID(),
                protocolId: MockProtocols.recoveryStack.id,
                peptide: MockPeptides.bpc157,
                date: calendar.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date(),
                dose: "250 mcg",
                notes: "",
                completed: false
            ),
            ProtocolEntry(
                id: UUID(),
                protocolId: MockProtocols.growthProtocol.id,
                peptide: MockPeptides.cjc1295,
                date: calendar.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date(),
                dose: "2 mg",
                notes: "",
                completed: false
            ),
        ]
    }

    static func complianceData(days: Int = 30) -> [(date: Date, compliance: Double)] {
        let calendar = Calendar.current
        var rng = SeededGenerator(seed: UInt64(bitPattern: Int64(days &* 31337)))
        return (0..<days).compactMap { dayOffset in
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { return nil }
            let compliance = Double.random(in: 0.6...1.0, using: &rng)
            return (date: date, compliance: compliance)
        }.reversed()
    }

    static func weeklyDoseData() -> [(day: String, count: Int)] {
        var rng = SeededGenerator(seed: 42)
        return [
            (day: "Mon", count: Int.random(in: 3...6, using: &rng)),
            (day: "Tue", count: Int.random(in: 3...6, using: &rng)),
            (day: "Wed", count: Int.random(in: 2...5, using: &rng)),
            (day: "Thu", count: Int.random(in: 3...6, using: &rng)),
            (day: "Fri", count: Int.random(in: 3...6, using: &rng)),
            (day: "Sat", count: Int.random(in: 1...4, using: &rng)),
            (day: "Sun", count: Int.random(in: 1...4, using: &rng)),
        ]
    }
}
