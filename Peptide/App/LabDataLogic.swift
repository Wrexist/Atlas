import Foundation

/// Pure-function operations on `UserProfile.labHistory`. Mirrors
/// the architectural pattern of `LifestyleDataLogic` — mutations
/// take `inout UserProfile`, read-only accessors take the profile
/// by value. Keeps the lab math unit-testable in isolation from
/// `DataStore`.
enum LabDataLogic {

    /// Inserts a new lab entry, or replaces an existing one with
    /// the same `id`. Newest-first sort order so list views read
    /// "most-recent-on-top" without an extra sort pass.
    static func saveLabValue(into profile: inout UserProfile, value: LabValue) {
        var updated = value
        updated.updatedAt = Date()
        if let index = profile.labHistory.firstIndex(where: { $0.id == value.id }) {
            profile.labHistory[index] = updated
        } else {
            profile.labHistory.append(updated)
        }
        profile.labHistory.sort { $0.date > $1.date }
    }

    /// Deletes one entry by id. Idempotent — calling twice does
    /// nothing on the second pass.
    static func deleteLabValue(from profile: inout UserProfile, id: UUID) {
        profile.labHistory.removeAll { $0.id == id }
    }

    /// Every entry for one panel, sorted oldest-first so callers
    /// drawing a chart can iterate forward. Powers the per-panel
    /// detail view's chart + trend math.
    static func entries(in profile: UserProfile, for panel: LabPanel) -> [LabValue] {
        profile.labHistory
            .filter { $0.panel == panel }
            .sorted { $0.date < $1.date }
    }

    /// Most-recent value for each panel the user has ever logged.
    /// Drives the labs-list view's "headline grid". Panels with
    /// no entries are omitted — the list grows as the user logs.
    static func latestPerPanel(in profile: UserProfile) -> [LatestSummary] {
        var byPanel: [LabPanel: LabValue] = [:]
        for entry in profile.labHistory {
            if let existing = byPanel[entry.panel] {
                if entry.date > existing.date {
                    byPanel[entry.panel] = entry
                }
            } else {
                byPanel[entry.panel] = entry
            }
        }
        // Preserve a stable display order — group by category, then
        // by the enum's natural declaration order within the
        // category. Without this, users would see panels jump
        // around as they add new draws.
        return LabPanel.allCases.compactMap { panel in
            guard let latest = byPanel[panel] else { return nil }
            let trend = computeTrend(entries: profile.labHistory.filter { $0.panel == panel })
            return LatestSummary(latest: latest, trend: trend)
        }
    }

    /// Direction between the two most-recent values for a panel.
    /// Returns `.stable` when only one entry exists (no comparison
    /// possible) or when the delta is below the 5%-of-value noise
    /// floor — saves the user from over-reading single-point drift.
    static func computeTrend(entries: [LabValue]) -> LabTrend {
        guard entries.count >= 2 else { return .stable }
        let sorted = entries.sorted { $0.date < $1.date }
        guard let latest = sorted.last,
              let previous = sorted.dropLast().last
        else { return .stable }
        let delta = latest.value - previous.value
        let threshold = abs(previous.value) * 0.05
        if abs(delta) < threshold {
            return .stable
        }
        return delta > 0 ? .rising(delta: delta) : .falling(delta: delta)
    }

    /// Composite return type for the headline grid. Each row gets
    /// the most recent value + the trend direction in one shot.
    struct LatestSummary: Identifiable {
        var id: UUID { latest.id }
        let latest: LabValue
        let trend: LabTrend
    }
}

/// Direction marker for the latest-vs-prior comparison.
/// `.rising` and `.falling` carry the absolute delta so the UI can
/// render "+24 ng/dL" or "−0.4 pg/mL"; `.stable` carries no value
/// because it explicitly means "below the noise floor".
enum LabTrend: Equatable, Sendable {
    case rising(delta: Double)
    case falling(delta: Double)
    case stable
}
