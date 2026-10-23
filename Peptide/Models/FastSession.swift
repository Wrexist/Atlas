import Foundation

/// The fasting schedules the tracker offers. The rawValue is what gets
/// persisted on `StoredFast.planRaw`, so existing cases must keep their
/// spelling; unknown values decode to `.custom` via `init(storedRaw:)`.
enum FastingProtocol: String, Codable, CaseIterable, Identifiable, Sendable {
    case twelve = "12:12"
    case fourteen = "14:10"
    case sixteen = "16:8"
    case eighteen = "18:6"
    case twenty = "20:4"
    case omad
    case custom

    var id: String { rawValue }

    init(storedRaw: String) {
        self = FastingProtocol(rawValue: storedRaw) ?? .custom
    }

    /// Fasting-window length the preset implies. One meal a day leaves a
    /// one-hour eating window. Custom starts at 16 h until the user picks.
    var defaultFastingHours: Double {
        switch self {
        case .twelve:   12
        case .fourteen: 14
        case .sixteen:  16
        case .eighteen: 18
        case .twenty:   20
        case .omad:     23
        case .custom:   16
        }
    }

    var title: String {
        switch self {
        case .omad:   String(localized: "OMAD", comment: "Fasting preset — one meal a day")
        case .custom: String(localized: "Custom", comment: "Fasting preset — user-picked length")
        default:      rawValue
        }
    }
}

/// One fasting window — open while `endedAt` is nil. Persisted through
/// `StoredFast`; this value type is what the engine, store and views
/// pass around.
struct FastSession: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date?
    var targetHours: Double
    var plan: FastingProtocol
    /// Schedule a local notification at `targetEnd` while the fast runs.
    var remindsAtEnd: Bool

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        targetHours: Double,
        plan: FastingProtocol,
        remindsAtEnd: Bool = false
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.targetHours = targetHours
        self.plan = plan
        self.remindsAtEnd = remindsAtEnd
    }

    var isActive: Bool { endedAt == nil }

    /// Absolute instant the goal is reached. Measured in elapsed seconds,
    /// not wall-clock hours, so a fast that spans a DST change still
    /// lasts its full target.
    var targetEnd: Date { startedAt.addingTimeInterval(targetHours * 3600) }
}
