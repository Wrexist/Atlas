import Foundation

/// Resolves a stored Today arrangement against the sections this build
/// ships. Pure so the "what survives an app update" rules are tested in
/// one place: ids this build doesn't know (a section since removed, or
/// one from a newer build on another device) are dropped, and sections
/// the stored order has never seen take their default slot.
enum TodayLayoutEngine {
    /// Every section in display order. Known stored ids keep their
    /// stored order (duplicates collapse to the first); each missing
    /// section lands right after the section that precedes it in the
    /// default order, or first when nothing does.
    static func sections(
        storedOrder: [String],
        defaults: [TodaySection] = TodaySection.allCases
    ) -> [TodaySection] {
        var result: [TodaySection] = []
        for id in storedOrder {
            guard let section = TodaySection(rawValue: id),
                  defaults.contains(section),
                  !result.contains(section) else { continue }
            result.append(section)
        }
        for (index, section) in defaults.enumerated() where !result.contains(section) {
            let placed = result
            let anchor = defaults[..<index].last { placed.contains($0) }
            let slot = anchor.flatMap { placed.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            result.insert(section, at: slot)
        }
        return result
    }

    /// `sections(storedOrder:defaults:)` without the hidden ones.
    static func visibleSections(
        storedOrder: [String],
        hidden: [String],
        defaults: [TodaySection] = TodaySection.allCases
    ) -> [TodaySection] {
        let hiddenIds = Set(hidden)
        return sections(storedOrder: storedOrder, defaults: defaults)
            .filter { !hiddenIds.contains($0.rawValue) }
    }
}
