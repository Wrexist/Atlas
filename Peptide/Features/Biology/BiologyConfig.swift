import Foundation

/// User's Biology tab preferences — which biomarkers to show, in
/// what order, and whether they've seen the one-shot intro. Lives
/// on `UserProfile` so it round-trips with the rest of the
/// profile through CloudKit / JSON / SwiftData sidecar.
///
/// Codable with default values everywhere so an older build
/// reading a newer profile (or vice-versa) decodes cleanly via
/// Swift's synthesized `init(from:)` — the synthesizer skips
/// missing keys when the property has a default.
struct BiologyConfig: Codable, Hashable, Sendable {
    /// Biomarkers the user wants on the Biology tab, in render
    /// order. Drives `BiomarkerListSection.visibleBiomarkers`.
    var visibleBiomarkers: [Biomarker] = Biomarker.defaultVisible
    /// Biomarkers the user has explicitly hidden. Catalog cases
    /// not present in either list are "available but not yet
    /// added" — `EditBiomarkersSheet` shows them in a third
    /// section so the user can pull them in.
    var hiddenBiomarkers: [Biomarker] = []
    /// One-shot welcome / intro sheet flag. Future commit may
    /// surface a brief explainer the first time a user opens the
    /// Biology tab; the flag prevents re-presentation. Defaults
    /// false so existing users — who never saw the intro — see
    /// it on next launch instead of getting silently skipped.
    var hasSeenIntro: Bool = false

    /// Canonical default config. Used by the manual decoder when
    /// the field is missing on an older profile JSON. Mirrors
    /// `Biomarker.defaultVisible` so a fresh install and an
    /// upgrading user converge on the same starting state.
    static let `default` = BiologyConfig()

    // MARK: - Mutations

    /// Reveal a previously-hidden (or never-added) biomarker by
    /// appending it to the visible list. Removes it from the
    /// hidden list if present so the catalog state stays
    /// consistent. No-op if already visible.
    mutating func show(_ biomarker: Biomarker) {
        hiddenBiomarkers.removeAll { $0 == biomarker }
        guard !visibleBiomarkers.contains(biomarker) else { return }
        visibleBiomarkers.append(biomarker)
    }

    /// Hide a currently-visible biomarker. Moves it to the
    /// hidden list so it's marked "deliberately off" rather than
    /// "never added" — matters for the Edit sheet's three-
    /// section layout.
    mutating func hide(_ biomarker: Biomarker) {
        visibleBiomarkers.removeAll { $0 == biomarker }
        guard !hiddenBiomarkers.contains(biomarker) else { return }
        hiddenBiomarkers.append(biomarker)
    }

    /// Reorder the visible list. Caller passes the full new
    /// order; we replace in place (no merging — the Edit sheet
    /// owns the source of truth during a drag session).
    mutating func reorder(_ newOrder: [Biomarker]) {
        // Filter to entries that are actually in the catalog so
        // a stale persisted ordering can't smuggle in a deleted
        // enum case. Catalog membership is the source of truth.
        visibleBiomarkers = newOrder.filter { Biomarker.allCases.contains($0) }
    }

    /// "Available but not yet added" — catalog cases not present
    /// in visible or hidden. Drives the Edit sheet's third
    /// section so the user can find biomarkers they haven't
    /// surfaced before.
    var availableBiomarkers: [Biomarker] {
        let claimed = Set(visibleBiomarkers).union(hiddenBiomarkers)
        return Biomarker.allCases.filter { !claimed.contains($0) }
    }
}
