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
        // Stable FNV-style hash, not String.hashValue: Swift randomizes
        // hashValue per process, so the "seeded" generator produced
        // different mock/screenshot data every launch — defeating the seed.
        let stableSeed = protocol_.name.utf8.reduce(UInt64(5381)) { ($0 &* 31) &+ UInt64($1) } &+ UInt64(days)
        var rng = SeededGenerator(seed: stableSeed)
        let startOfProtocol = calendar.startOfDay(for: protocol_.startDate)
        let endOfProtocol = calendar.startOfDay(for: protocol_.endDate)

        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let dayStart = calendar.startOfDay(for: date)

            // Only generate entries within the protocol's active date range
            guard dayStart >= startOfProtocol && dayStart <= endOfProtocol else { continue }

            for peptide in protocol_.peptides {
                let schedule = protocol_.schedule(for: peptide.id)
                guard schedule.isActive(on: date, calendar: calendar) else { continue }

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

}
