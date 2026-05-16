import Foundation

/// Single dose marker rendered on the Track-tab calendar. Carries enough
/// state for the day cell to render the right-coloured dot (logged) or
/// outlined ring (scheduled) plus the per-day detail panel to list the
/// matching cards.
struct CalendarDoseMark: Identifiable, Hashable {
    enum Kind: Hashable { case logged, scheduled }

    let id = UUID()
    let kind: Kind
    let day: Date
    let peptideID: UUID
    let peptideName: String
    let peptideAbbreviation: String
    let dose: String
    let time: String?
    let injectionSite: String?
    /// Set when the mark came from a real ProtocolEntry — the detail panel
    /// passes this to any per-row action (open, edit, delete) once those
    /// affordances ship. Nil for synthetic scheduled marks.
    let entryID: UUID?
    /// Status of the owning protocol at the time the mark was built.
    /// Synthetic scheduled marks are only emitted for `.active`, but a
    /// logged entry from a now-paused or completed protocol still shows
    /// on the calendar — render it with a muted treatment so the user
    /// can distinguish historical from active doses.
    let protocolStatus: ProtocolStatus
}

/// Builds a per-day map of marks across both logged entries and scheduled
/// future doses for a given month. Logged comes from `dataStore.entries`
/// directly; scheduled is synthesized by walking each active protocol's
/// schedule (daysOfWeek + cycle window) and emitting one mark per
/// peptide × day for the days that don't already have a logged entry
/// for that compound (so the calendar doesn't double-stamp).
enum DoseDayMap {

    static func build(
        for monthDate: Date,
        entries: [ProtocolEntry],
        protocols: [PeptideProtocol],
        calendar: Calendar = .current
    ) -> [Date: [CalendarDoseMark]] {
        let cal = calendar
        let grid = CalendarMonth.grid(for: monthDate, firstWeekday: cal.firstWeekday, calendar: cal)
        guard let monthStart = grid.first, let monthEnd = grid.last else { return [:] }

        var result: [Date: [CalendarDoseMark]] = [:]

        // Index protocols by ID so we can attach the owning protocol's
        // current status to each logged mark. Used by the detail panel
        // to render historical/paused entries with a muted style.
        let protocolStatusByID = Dictionary(
            uniqueKeysWithValues: protocols.map { ($0.id, $0.status) }
        )

        // Logged — group entries that fall inside the visible window by day.
        for entry in entries {
            let day = cal.startOfDay(for: entry.date)
            guard day >= monthStart && day <= monthEnd else { continue }
            let mark = CalendarDoseMark(
                kind: .logged,
                day: day,
                peptideID: entry.peptide.id,
                peptideName: entry.peptide.name,
                peptideAbbreviation: entry.peptide.abbreviation,
                dose: entry.dose,
                time: timeString(for: entry.date, calendar: cal),
                injectionSite: entry.injectionSite,
                entryID: entry.id,
                protocolStatus: protocolStatusByID[entry.protocolId] ?? .active
            )
            result[day, default: []].append(mark)
        }

        // Scheduled — for every day in the grid, emit one mark per
        // (active-protocol × peptide) when the day's weekday matches the
        // schedule and the day sits inside the cycle window. Skip when a
        // logged mark for the same compound already exists that day so the
        // dot row doesn't show two of the same colour.
        for day in grid {
            for proto in protocols where proto.status == .active {
                guard isDayInCycle(day, protocol: proto, calendar: cal) else { continue }
                guard isWeekdayMatch(day: day, schedule: proto.schedule, calendar: cal) else { continue }
                for peptide in proto.peptides {
                    // Suppress when *any* mark for this compound on this
                    // day already exists — covers both the "logged
                    // already" case and the "another active protocol in
                    // the same loop already emitted a scheduled mark for
                    // the shared peptide" case. Without this second
                    // check the calendar shows two same-coloured dots
                    // for any peptide that appears in two stacks.
                    let alreadyMarked = result[day]?.contains(where: {
                        $0.peptideID == peptide.id
                    }) ?? false
                    if alreadyMarked { continue }

                    let mark = CalendarDoseMark(
                        kind: .scheduled,
                        day: day,
                        peptideID: peptide.id,
                        peptideName: peptide.name,
                        peptideAbbreviation: peptide.abbreviation,
                        dose: proto.schedule.customDose ?? peptide.dosageRange,
                        time: proto.schedule.preferredTimes.first,
                        injectionSite: nil,
                        entryID: nil,
                        // Synthetic scheduled marks only emit for
                        // active protocols (guard above on line 69).
                        protocolStatus: .active
                    )
                    result[day, default: []].append(mark)
                }
            }
        }

        return result
    }

    // MARK: - Predicates

    private static func isDayInCycle(
        _ day: Date,
        protocol proto: PeptideProtocol,
        calendar: Calendar
    ) -> Bool {
        let start = calendar.startOfDay(for: proto.startDate)
        guard day >= start else { return false }
        let weeks = proto.safeCycleLengthWeeks
        guard let end = calendar.date(byAdding: .day, value: weeks * 7, to: start) else { return true }
        return day < end
    }

    private static func isWeekdayMatch(
        day: Date,
        schedule: ProtocolSchedule,
        calendar: Calendar
    ) -> Bool {
        // ProtocolSchedule encodes daysOfWeek as ISO 1=Mon…7=Sun, while
        // Calendar.weekday is 1=Sun…7=Sat — convert before comparing.
        let weekday = calendar.component(.weekday, from: day)
        let iso = weekday == 1 ? 7 : weekday - 1
        return schedule.daysOfWeek.contains(iso)
    }

    private static func timeString(for date: Date, calendar: Calendar) -> String {
        date.formatted(.dateTime.hour().minute())
    }
}
