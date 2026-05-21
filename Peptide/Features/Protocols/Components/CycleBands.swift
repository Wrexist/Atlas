import Foundation
import SwiftUI

/// Toggles the calendar between per-day dose dots and per-week cycle
/// bands. Surfaced as a segmented control in `TrackCalendarSection`;
/// `CalendarMonthView` reads it to swap its row indicator strip.
enum CalendarDisplayMode: String, CaseIterable, Identifiable {
    case schedule
    case cycle

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .schedule: "Schedule"
        case .cycle:    "Cycle"
        }
    }
}

/// One coloured stripe rendered on a week row in cycle mode. Identifies
/// which protocol contributed it so multiple stacks can stack cleanly
/// without duplicate colours collapsing.
struct CycleBand: Identifiable, Hashable {
    let id: UUID            // protocol id
    let name: String        // protocol name (used for accessibility)
    let color: Color
}

/// Computes per-week-row cycle bands from a list of protocols + the
/// 42-cell calendar grid. A protocol contributes a band to a week row
/// when any day in that row falls inside the protocol's
/// `[startDate, startDate + cycleLengthWeeks * 7)` window. The first
/// peptide's `VialPalette` colour drives the band so the bands match
/// the dot colours used in schedule mode.
enum CycleBands {

    /// Returns 6 arrays, one per row in the calendar grid. Each array
    /// is the set of bands to paint on that row. Empty arrays mean
    /// "off week" — no bands rendered.
    static func bands(
        for grid: [Date],
        protocols: [PeptideProtocol],
        calendar: Calendar = .current
    ) -> [[CycleBand]] {
        precondition(grid.count == 42, "Expected the standard 6x7 calendar grid")

        let active = protocols.filter { $0.status == .active }

        return (0..<6).map { row in
            let weekStart = grid[row * 7]
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart

            return active.compactMap { proto -> CycleBand? in
                guard isProtocolActive(in: weekStart..<weekEnd, protocol: proto, calendar: calendar) else {
                    return nil
                }
                let primaryName = proto.peptides.first?.name ?? proto.name
                let palette = VialPalette.colors(for: primaryName)
                return CycleBand(id: proto.id, name: proto.name, color: palette.fill)
            }
        }
    }

    private static func isProtocolActive(
        in week: Range<Date>,
        protocol proto: PeptideProtocol,
        calendar: Calendar
    ) -> Bool {
        let start = calendar.startOfDay(for: proto.startDate)
        let weeks = proto.safeCycleLengthWeeks
        let end = calendar.date(byAdding: .day, value: weeks * 7, to: start) ?? start
        // The protocol is "active" in a week row if its [start, end)
        // window overlaps the row's [weekStart, weekEnd) window. The
        // standard half-open interval overlap test reads cleanly here.
        return start < week.upperBound && end > week.lowerBound
    }
}
