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

    /// Rewrites every active protocol's default + per-peptide
    /// preferred times by `hours` (positive = later in the local
    /// day, negative = earlier). Ordering is preserved; the new
    /// strings are formatted in the same `h:mm a` shape the
    /// schedule editor produces, locale-aware so a French user
    /// who shifts +3 hours sees "11:00" → "14:00", not "11:00 AM"
    /// → "14:00 AM".
    ///
    /// Doesn't mutate the protocol's `daysOfWeek`, cycle config,
    /// or anything else — strictly a clock translation. A
    /// future enhancement could distribute the shift across
    /// multiple days for receptor-stability reasons; for v1 the
    /// shift is immediate, matching the typical traveller's
    /// expectation that "I land, my doses are now on local time".
    static func shiftProtocolTimes(
        in protocols: inout [PeptideProtocol],
        byHours hours: Int
    ) {
        for index in protocols.indices {
            let original = protocols[index]
            guard original.status == .active else { continue }
            let updated = PeptideProtocol(
                id: original.id,
                name: original.name,
                peptides: original.peptides,
                schedule: shiftSchedule(original.schedule, byHours: hours),
                peptideSchedules: original.peptideSchedules.mapValues {
                    shiftSchedule($0, byHours: hours)
                },
                cycleLengthWeeks: original.cycleLengthWeeks,
                washoutWeeks: original.washoutWeeks,
                startDate: original.startDate,
                status: original.status,
                notes: original.notes,
                authorName: original.authorName,
                authorHandle: original.authorHandle,
                forkedFromStackId: original.forkedFromStackId,
                createdAt: original.createdAt
            )
            protocols[index] = updated
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
    /// by `hours`. Times that fail to parse are passed through
    /// unchanged — better to leave a stray "Around lunch" string
    /// alone than to lose it during a migration.
    static func shiftSchedule(_ schedule: ProtocolSchedule, byHours hours: Int) -> ProtocolSchedule {
        let shifted = schedule.preferredTimes.map { shiftTime($0, byHours: hours) }
        return ProtocolSchedule(
            daysOfWeek: schedule.daysOfWeek,
            timesPerDay: schedule.timesPerDay,
            preferredTimes: shifted,
            intervalDays: schedule.intervalDays,
            intervalAnchor: schedule.intervalAnchor
        )
    }

    /// Single time-string shift. Public-on-the-enum so the prompt
    /// preview UI can render "your 8:00 AM dose → 11:00 AM" without
    /// the caller having to recreate the parsing logic.
    static func shiftTime(_ string: String, byHours hours: Int) -> String {
        guard let date = parseTime(string) else { return string }
        let calendar = Calendar.current
        guard let shifted = calendar.date(byAdding: .hour, value: hours, to: date) else {
            return string
        }
        return formatTime(shifted)
    }

    // MARK: - Parsing helpers

    // DateFormatter is documented thread-safe for read-only use
    // after configuration. `nonisolated(unsafe)` opts these
    // statics out of Swift 6's shared-mutable-state check since
    // they're only ever read.
    nonisolated(unsafe) private static let parseFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    nonisolated(unsafe) private static let formatFormatter: DateFormatter = {
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
