import Foundation

/// A daily supplement — creatine, vitamin D, omega-3 — checked off once a
/// day. Deliberately not a protocol: no cycle, no dose schedule, no
/// inventory, just "did I take it today".
///
/// Travels on `UserProfile` (the residual sync blob) so the list and its
/// history follow the user to every device. The taken days live on the
/// supplement itself as compact day keys rather than one record per tap,
/// so a year of five supplements stays a few kilobytes.
struct Supplement: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    /// Free text in the user's own words ("5 g", "2 000 IE"). Empty is
    /// fine — plenty of people just take "one".
    var dose: String
    /// SF Symbol shown on the Today row.
    var symbol: String
    /// When in the day it's taken, as minutes after local midnight. Nil
    /// means any time; it also orders the Today rows.
    var minuteOfDay: Int?
    /// Fires a nudge at `minuteOfDay` on days it isn't checked off yet.
    /// Ignored while `minuteOfDay` is nil.
    var reminderEnabled: Bool
    /// Local days it was taken, as `SupplementEngine.dayKey` values in
    /// ascending order. Sorted so the encoded blob is stable byte for byte.
    var takenDays: [String]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        dose: String = "",
        symbol: String = Supplement.defaultSymbol,
        minuteOfDay: Int? = nil,
        reminderEnabled: Bool = false,
        takenDays: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.dose = dose
        self.symbol = symbol
        self.minuteOfDay = minuteOfDay
        self.reminderEnabled = reminderEnabled
        self.takenDays = takenDays
        self.createdAt = createdAt
    }

    static let defaultSymbol = "pills.fill"

    /// "08:00" in the user's clock style, or nil for any time of day.
    func timeText(calendar: Calendar = .current) -> String? {
        guard let minuteOfDay,
              let date = calendar.date(
                  bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0,
                  of: calendar.startOfDay(for: Date())
              )
        else { return nil }
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// "5 g · 08:00", whichever parts are set.
    var detailText: String {
        [dose.isEmpty ? nil : dose, timeText()].compactMap { $0 }.joined(separator: " · ")
    }
}

/// The common supplements offered as one-tap presets, with a typical
/// daily dose filled in. Named in the user's language when added; the
/// stored supplement keeps that text, so a preset is only a starting point.
enum SupplementPreset: String, CaseIterable, Identifiable, Sendable {
    case creatine, vitaminD, omega3, magnesium, zinc, vitaminC, multivitamin, iron

    var id: String { rawValue }

    var name: String {
        switch self {
        case .creatine:     String(localized: "Creatine", comment: "Supplement preset")
        case .vitaminD:     String(localized: "Vitamin D", comment: "Supplement preset")
        case .omega3:       String(localized: "Omega-3", comment: "Supplement preset")
        case .magnesium:    String(localized: "Magnesium", comment: "Supplement preset")
        case .zinc:         String(localized: "Zinc", comment: "Supplement preset")
        case .vitaminC:     String(localized: "Vitamin C", comment: "Supplement preset")
        case .multivitamin: String(localized: "Multivitamin", comment: "Supplement preset")
        case .iron:         String(localized: "Iron", comment: "Supplement preset")
        }
    }

    var dose: String {
        switch self {
        case .creatine:     "5 g"
        case .vitaminD:     String(localized: "2,000 IU", comment: "Vitamin D preset dose — international units")
        case .omega3:       "1 g"
        case .magnesium:    "300 mg"
        case .zinc:         "15 mg"
        case .vitaminC:     "500 mg"
        case .multivitamin: String(localized: "1 tablet", comment: "Multivitamin preset dose")
        case .iron:         "14 mg"
        }
    }

    var symbol: String {
        switch self {
        case .creatine:     "bolt.fill"
        case .vitaminD:     "sun.max.fill"
        case .omega3:       "fish.fill"
        case .magnesium:    "moon.zzz.fill"
        case .zinc:         "shield.fill"
        case .vitaminC:     "leaf.fill"
        case .multivitamin: "pills.fill"
        case .iron:         "drop.fill"
        }
    }

    func makeSupplement(createdAt: Date = Date()) -> Supplement {
        Supplement(name: name, dose: dose, symbol: symbol, createdAt: createdAt)
    }
}
