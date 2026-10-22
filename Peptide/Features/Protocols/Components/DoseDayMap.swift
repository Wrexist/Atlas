import Foundation

/// Single dose marker rendered on the Track-tab calendar. Carries enough
/// state for the day cell to render the right-coloured dot (logged) or
/// outlined ring (scheduled) plus the per-day detail panel to list the
/// matching cards.
struct CalendarDoseMark: Identifiable, Hashable {
    enum Kind: Hashable { case logged, scheduled }

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

    /// Derived from content rather than minted per build, so a rebuilt map
    /// keeps the same identities and `ForEach` can diff and animate it.
    /// Unique per day: logged marks differ by entry, and scheduled marks
    /// are emitted at most once per compound per day.
    var id: String {
        "\(kind)-\(day.timeIntervalSinceReferenceDate)-\(peptideID)-\(entryID?.uuidString ?? "")"
    }
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

        // Real entries inside the visible window, grouped by day. Only a
        // completed entry counts as logged; a pending or missed one is
        // still just scheduled.
        for entry in entries {
            let day = cal.startOfDay(for: entry.date)
            guard day >= monthStart && day <= monthEnd else { continue }
            let mark = CalendarDoseMark(
                kind: entry.completed ? .logged : .scheduled,
                day: day,
                peptideID: entry.peptide.id,
                peptideName: entry.peptide.name,
                peptideAbbreviation: entry.peptide.abbreviation,
                dose: entry.dose,
                time: timeString(for: entry.actualTime ?? entry.date, calendar: cal),
                injectionSite: entry.injectionSite,
                entryID: entry.id,
                protocolStatus: protocolStatusByID[entry.protocolId] ?? .active
            )
            result[day, default: []].append(mark)
        }

        // Scheduled — for every day in the grid, emit one mark per
        // (active-protocol × peptide) when the peptide's own schedule (its
        // override, else the protocol default — weekly or every-N-days)
        // lands on that day inside the cycle window. Skip when a
        // logged mark for the same compound already exists that day so the
        // dot row doesn't show two of the same colour.
        for day in grid {
            for proto in protocols where proto.status == .active {
                guard CyclePhaseEngine.isOnCycle(day, protocol: proto, calendar: cal) else { continue }
                for peptide in proto.peptides {
                    let schedule = proto.schedule(for: peptide.id)
                    guard schedule.isActive(on: day, protocolStart: proto.startDate, calendar: cal)
                    else { continue }
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
                        // Never the database research range: that would present a
                        // reference figure as the user's own dose (Guideline 1.4.1).
                        dose: schedule.customDose ?? String(localized: "Dose not set"),
                        time: schedule.preferredTimes.first,
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

    private static func timeString(for date: Date, calendar: Calendar) -> String {
        date.formatted(.dateTime.hour().minute())
    }
}
