import Foundation

enum MockProtocols {
    static let all: [PeptideProtocol] = [recoveryStack, growthProtocol, cognitiveEnhancement, immuneBoost]

    static let recoveryStack = PeptideProtocol(
        id: UUID(),
        name: "Recovery Stack",
        peptides: [MockPeptides.bpc157, MockPeptides.tb500, MockPeptides.ghkCu],
        schedule: ProtocolSchedule(
            daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
            timesPerDay: 2,
            preferredTimes: ["8:00 AM", "8:00 PM"]
        ),
        cycleLengthWeeks: 8,
        startDate: Calendar.current.date(byAdding: .weekOfYear, value: -3, to: Date()) ?? Date(),
        status: .active,
        notes: "Focus on tendon and joint recovery. BPC-157 AM and PM, TB-500 2x/week, GHK-Cu daily."
    )

    static let growthProtocol = PeptideProtocol(
        id: UUID(),
        name: "Growth Protocol",
        peptides: [MockPeptides.cjc1295, MockPeptides.igf1lr3, MockPeptides.tesamorelin],
        schedule: ProtocolSchedule(
            daysOfWeek: [1, 3, 5],
            timesPerDay: 1,
            preferredTimes: ["9:00 PM"]
        ),
        cycleLengthWeeks: 12,
        startDate: Calendar.current.date(byAdding: .weekOfYear, value: -5, to: Date()) ?? Date(),
        status: .active,
        notes: "Evening administration for synergy with natural GH pulse. 3x weekly cycle."
    )

    static let cognitiveEnhancement = PeptideProtocol(
        id: UUID(),
        name: "Cognitive Enhancement",
        peptides: [MockPeptides.semax, MockPeptides.selank],
        schedule: ProtocolSchedule(
            daysOfWeek: [1, 2, 3, 4, 5],
            timesPerDay: 2,
            preferredTimes: ["7:00 AM", "2:00 PM"]
        ),
        cycleLengthWeeks: 4,
        startDate: Calendar.current.date(byAdding: .weekOfYear, value: -6, to: Date()) ?? Date(),
        status: .completed,
        notes: "Weekday protocol for focus and productivity. Morning and early afternoon dosing."
    )

    static let immuneBoost = PeptideProtocol(
        id: UUID(),
        name: "Immune Support",
        peptides: [MockPeptides.thymosinAlpha1, MockPeptides.ll37],
        schedule: ProtocolSchedule(
            daysOfWeek: [1, 3, 5],
            timesPerDay: 1,
            preferredTimes: ["10:00 AM"]
        ),
        cycleLengthWeeks: 6,
        startDate: Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date(),
        status: .paused,
        notes: "Paused due to travel. Resume on return. TA1 3x/week with LL-37 daily."
    )
}
