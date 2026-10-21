import SwiftUI

/// A block of the Today scroll the user can move or hide from the
/// "Edit Today" sheet. Raw values are persisted on the profile, so they
/// are stable ids — rename a case freely, never its raw value. Case
/// order is the default layout.
///
/// The welcome header, jump bar and reminder banner are not here: they
/// are Today's chrome and stay pinned above the sections.
enum TodaySection: String, CaseIterable, Identifiable, Sendable {
    case atAGlance = "atAGlance"
    case coaching = "coaching"
    case weeklyRecap = "weeklyRecap"
    case habits = "habits"
    case checklist = "checklist"
    case doses = "doses"
    case wellness = "wellness"
    case movement = "movement"
    case overview = "overview"
    case momentum = "momentum"
    case explore = "explore"
    case timeline = "timeline"
    case healthMonitor = "healthMonitor"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .atAGlance: String(localized: "At a glance")
        case .coaching: String(localized: "Coaching")
        case .weeklyRecap: String(localized: "Weekly recap")
        case .habits: String(localized: "Habits")
        case .checklist: String(localized: "Daily checklist")
        case .doses: String(localized: "Doses")
        case .wellness: String(localized: "Wellness check-in")
        case .movement: String(localized: "Movement")
        case .overview: String(localized: "Overview")
        case .momentum: String(localized: "Goal & Atlas Score")
        case .explore: String(localized: "Explore")
        case .timeline: String(localized: "Timeline")
        case .healthMonitor: String(localized: "Health monitor")
        }
    }

    var systemImage: String {
        switch self {
        case .atAGlance: "gauge.with.needle"
        case .coaching: "sparkles"
        case .weeklyRecap: "calendar.badge.clock"
        case .habits: "checkmark.circle"
        case .checklist: "checklist"
        case .doses: "syringe"
        case .wellness: "heart.text.square"
        case .movement: "figure.run"
        case .overview: "square.grid.2x2"
        case .momentum: "flag.checkered"
        case .explore: "text.magnifyingglass"
        case .timeline: "calendar.day.timeline.left"
        case .healthMonitor: "waveform.path.ecg"
        }
    }
}

/// The user's Today arrangement. Lives on `UserProfile` beside
/// `BiologyConfig` so it follows the user across devices.
///
/// Stored as raw ids rather than `TodaySection` values so a profile
/// written by a newer build — with a section this build doesn't know —
/// still decodes; `TodayLayoutEngine` drops the unknown ids on read.
/// An empty `order` means "never rearranged" and reads as the default.
struct TodayLayout: Codable, Hashable, Sendable {
    var order: [String] = []
    var hidden: [String] = []

    static let `default` = TodayLayout()

    /// Every section in display order, hidden ones included.
    var sections: [TodaySection] {
        TodayLayoutEngine.sections(storedOrder: order)
    }

    /// The sections Today renders, in order.
    var visibleSections: [TodaySection] {
        TodayLayoutEngine.visibleSections(storedOrder: order, hidden: hidden)
    }

    func isHidden(_ section: TodaySection) -> Bool {
        hidden.contains(section.rawValue)
    }

    mutating func setHidden(_ section: TodaySection, _ isHidden: Bool) {
        hidden.removeAll { $0 == section.rawValue }
        if isHidden { hidden.append(section.rawValue) }
    }

    /// Writes the full resolved order back, so sections this build
    /// inserted at their default position are pinned where the user
    /// last saw them.
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var next = sections
        next.move(fromOffsets: source, toOffset: destination)
        order = next.map(\.rawValue)
    }
}

extension TodayLayout {
    /// Missing-key-tolerant, like `ProfileExtension`: the synthesized
    /// decoder throws on an absent key even when the property has a
    /// default. In an extension so the memberwise init survives.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = try c.decodeIfPresent([String].self, forKey: .order) ?? []
        hidden = try c.decodeIfPresent([String].self, forKey: .hidden) ?? []
    }
}
