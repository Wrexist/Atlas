import Foundation

/// Pure builder for the home-screen / lock-screen widget payload.
/// Extracted from `DataStore.updateWidgetData` so the snapshot shape
/// is unit-testable and the side effects (PersistenceService write,
/// WidgetCenter reload) stay isolated on DataStore.
///
/// The widget target consumes the resulting `WidgetData` verbatim via
/// `PersistenceService.shared.loadWidgetData()`, so any drift in this
/// transformation surfaces immediately on the next render — there's
/// no schema migration between phone and widget.
enum WidgetSnapshotBuilder {

    /// Captures the inputs the widget cares about: today's entries
    /// (regardless of completion) and the next pending dose. The next
    /// dose is passed separately rather than recomputed because
    /// `DataStore.nextDose` is cached and shouldn't be re-derived.
    static func build(today: [ProtocolEntry], next: ProtocolEntry?) -> WidgetData {
        let completed = today.filter(\.completed).count

        // Surface the next 3 doses (chronological) for the Medium widget's
        // today list — see slot 7 in docs/APP_STORE_SCREENSHOTS_GUIDE_1.md.
        let upcoming = today
            .sorted { $0.date < $1.date }
            .prefix(3)
            .map { entry in
                WidgetDoseSlot(
                    peptideName: entry.peptide.abbreviation,
                    dose: entry.dose,
                    time: entry.date,
                    completed: entry.completed
                )
            }

        return WidgetData(
            nextPeptideName: next?.peptide.abbreviation ?? "",
            nextDose: next?.dose ?? "",
            nextDoseTime: next?.date,
            completedToday: completed,
            totalToday: today.count,
            lastUpdated: Date(),
            upcoming: Array(upcoming)
        )
    }
}
