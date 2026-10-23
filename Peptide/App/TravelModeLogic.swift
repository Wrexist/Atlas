import Foundation

/// Pure-function helpers for the travel-mode schedule shift. The
/// detection lives in `TimezoneChangeDetector`; this file owns
/// the actual `ProtocolSchedule.preferredTimes` rewrites + the
/// "remember the new zone so we don't re-prompt" flag flips.
///
/// Mutations operate on `inout UserProfile` and `inout
/// [PeptideProtocol]` so the unit tests can drive the logic
/// without standing up `DataStore`.
enum TravelModeLogic {

    /// Rewrites every non-completed protocol's default + per-peptide
    /// preferred times by `minutes` (positive = later in the local
    /// day, negative = earlier). Paused protocols shift too, so one
    /// resumed after the trip doesn't fire on the old clock — the
    /// acknowledged zone means nothing re-prompts. Ordering is
    /// preserved; the new strings use the `h:mm a` shape the
    /// schedule editor produces.
    ///
    /// The shift keeps each dose at the same absolute moment, so a
    /// time that crosses midnight moves its schedule's days with it
    /// (an 11:00 PM Monday dose shifted +3 h lands at 2:00 AM
    /// Tuesday). Cycle config is untouched.
    static func shiftProtocolTimes(
        in protocols: inout [PeptideProtocol],
        byMinutes minutes: Int
    ) {
        for index in protocols.indices {
            let original = protocols[index]
            guard original.status != .completed else { continue }
            protocols[index] = original.with(
                schedule: shiftSchedule(original.schedule, byMinutes: minutes),
                peptideSchedules: original.peptideSchedules.mapValues {
                    shiftSchedule($0, byMinutes: minutes)
                }
            )
        }
    }

    /// Records the post-shift (or post-decline) timezone so the
    /// detector won't fire again until the user crosses into a
    /// *different* zone. Single canonical write site for the flag.
    static func acknowledgeTimezoneChange(
        in profile: inout UserProfile,
        to identifier: String
    ) {
        profile.lastKnownTimezoneIdentifier = identifier
    }

    /// Returns `schedule` with every `preferredTimes` entry shifted
    /// by `minutes`. Times that fail to parse are passed through
    /// unchanged — better to leave a stray "Around lunch" string
    /// alone than to lose it during a migration.
    ///
    /// When every parsed time crosses midnight the same way, the
    /// weekdays and interval anchor move by that day. A schedule
    /// whose times straddle midnight (8:00 AM and 11:00 PM, +3 h)
    /// can't be expressed with one set of days, so its days stay.
    static func shiftSchedule(_ schedule: ProtocolSchedule, byMinutes minutes: Int) -> ProtocolSchedule {
        let shifted = schedule.preferredTimes.map { shiftedTime($0, byMinutes: minutes) }
        let dayOffsets = Set(shifted.compactMap { $0.dayOffset })
        let dayOffset = dayOffsets.count == 1 ? dayOffsets.first ?? 0 : 0
        return ProtocolSchedule(
            daysOfWeek: schedule.daysOfWeek.map { rotateWeekday($0, by: dayOffset) }.sorted(),
            timesPerDay: schedule.timesPerDay,
            preferredTimes: shifted.map { $0.time },
            customDose: schedule.customDose,
            intervalDays: schedule.intervalDays,
            intervalAnchor: schedule.intervalAnchor.flatMap {
                Calendar.current.date(byAdding: .day, value: dayOffset, to: $0)
            }
        )
    }

    /// Single time-string shift. Public-on-the-enum so the prompt
    /// preview UI can render "your 8:00 AM dose → 11:00 AM" without
    /// the caller having to recreate the parsing logic.
    static func shiftTime(_ string: String, byMinutes minutes: Int) -> String {
        shiftedTime(string, byMinutes: minutes).time
    }

    /// The shifted time plus how many days it crossed (-1, 0, +1),
    /// or a nil offset when the string doesn't parse.
    private static func shiftedTime(
        _ string: String,
        byMinutes minutes: Int
    ) -> (time: String, dayOffset: Int?) {
        let calendar = Calendar.current
        guard let date = parseTime(string) else { return (string, nil) }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let total = (parts.hour ?? 0) * 60 + (parts.minute ?? 0) + minutes
        let minutesPerDay = 24 * 60
        let dayOffset = Int((Double(total) / Double(minutesPerDay)).rounded(.down))
        let minuteOfDay = total - dayOffset * minutesPerDay
        guard let shifted = calendar.date(
            bySettingHour: minuteOfDay / 60,
            minute: minuteOfDay % 60,
            second: 0,
            of: date
        ) else { return (string, nil) }
        return (formatTime(shifted), dayOffset)
    }

    /// Moves a 1=Mon…7=Sun weekday by `days`, wrapping the week.
    private static func rotateWeekday(_ weekday: Int, by days: Int) -> Int {
        ((weekday - 1 + days) % 7 + 7) % 7 + 1
    }

    // MARK: - Parsing helpers

    private static let parseFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let formatFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func parseTime(_ string: String) -> Date? {
        parseFormatter.date(from: string)
    }

    private static func formatTime(_ date: Date) -> String {
        formatFormatter.string(from: date)
    }
}
