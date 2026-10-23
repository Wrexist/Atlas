import Foundation

/// Day browsing on Today: which sections a past day keeps, and the
/// day-scoped reads behind the ones that stay. Speaks the same day
/// offsets as `MealDaySwitcher` (0 = today, -1 = yesterday) so Today and
/// Meals share one picker and one lookback floor. Pure so the
/// "per-day vs today-only" split lives in one tested place.
enum TodayDayEngine {
    /// Every block of the Today scroll that can come and go with the day.
    enum Section: CaseIterable, Sendable {
        /// Jump chips and the "+ Log" quick-log button.
        case quickActions
        case notificationBanner
        /// Live HealthKit trio — latest recovery and last night's sleep.
        case atAGlance
        case coaching
        case weeklyRecap
        case habits
        case checklist
        case doses
        /// The check-in prompt; a past day's check-in shows in the overview and timeline.
        case wellness
        case movement
        case overview
        /// Goal countdown and Atlas Score — where the user stands now.
        case momentum
        /// Research assistant and protocol discovery rows.
        case explore
        case timeline
        /// Rolling personal-range HRV / RHR / sleep grid.
        case healthMonitor
    }

    /// Sections whose content is recorded per calendar day, so they can
    /// show any day. Everything else describes "now" and only shows today.
    static let perDaySections: Set<Section> = [.habits, .checklist, .doses, .movement, .overview, .timeline]

    static func isVisible(_ section: Section, isToday: Bool) -> Bool {
        isToday || perDaySections.contains(section)
    }

    /// Offset 0 or later is today — the picker never selects the future.
    static func isToday(offset: Int) -> Bool {
        offset >= 0
    }

    /// Start of the browsed day, clamped to today and the shared
    /// one-year lookback floor.
    static func day(offset: Int, from now: Date = Date(), calendar: Calendar = .current) -> Date {
        LifestyleDataLogic.mealDay(offset: offset, from: now, calendar: calendar)
    }

    /// Midnight-to-midnight window of `day`, for windowed store fetches.
    static func dayRange(for day: Date, calendar: Calendar = .current) -> Range<Date> {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return start..<end
    }

    /// Doses scheduled on `day`, oldest first. Keeps entries of any
    /// protocol still on file — a cycle completed since then still
    /// happened that day — and drops orphans of deleted protocols.
    static func doseEntries(
        _ entries: [ProtocolEntry],
        on day: Date,
        protocolIds: Set<UUID>,
        calendar: Calendar = .current
    ) -> [ProtocolEntry] {
        entries
            .filter { calendar.isDate($0.date, inSameDayAs: day) && protocolIds.contains($0.protocolId) }
            .sorted { $0.date < $1.date }
    }
}
