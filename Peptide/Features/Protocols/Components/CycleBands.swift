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
/// when any day in that row falls in one of the protocol's on-cycle
/// phases (`CyclePhaseEngine.isOnCycle`), so wash-out weeks stay
/// unpainted and repeat cycles light up again. The first
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
        // A render path must never trap on a malformed grid — degrade
        // to six empty rows (the documented "off week" state) and flag
        // it in debug builds only.
        guard grid.count == 42 else {
            assertionFailure("Expected the standard 6x7 calendar grid, got \(grid.count)")
            return Array(repeating: [CycleBand](), count: 6)
        }

        let active = protocols.filter { $0.status == .active }

        return (0..<6).map { row in
            let week = grid[(row * 7)..<(row * 7 + 7)]

            return active.compactMap { proto -> CycleBand? in
                guard week.contains(where: { CyclePhaseEngine.isOnCycle($0, protocol: proto, calendar: calendar) }) else {
                    return nil
                }
                let primaryName = proto.peptides.first?.name ?? proto.name
                let palette = VialPalette.colors(for: primaryName)
                return CycleBand(id: proto.id, name: proto.name, color: palette.fill)
            }
        }
    }
}
