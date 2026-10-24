import Foundation

/// User's Biology tab preferences — which biomarkers to show, and in
/// what order. Lives
/// on `UserProfile` so it round-trips with the rest of the
/// profile through CloudKit / JSON / SwiftData sidecar.
///
/// Coding is hand-written (see the extension below): a missing
/// key falls back to its default and an unknown biomarker raw value
/// is dropped, so an older build reading a newer profile (or
/// vice-versa) never fails — a failure here would empty the whole
/// `ProfileExtension` it lives in.
struct BiologyConfig: Codable, Hashable, Sendable {
    /// Biomarkers the user wants on the Biology tab, in render
    /// order. Drives `BiomarkerListSection.visibleBiomarkers`.
    var visibleBiomarkers: [Biomarker] = Biomarker.defaultVisible
    /// Biomarkers the user has explicitly hidden. Catalog cases
    /// not present in either list are "available but not yet
    /// added" — `EditBiomarkersSheet` shows them in a third
    /// section so the user can pull them in.
    var hiddenBiomarkers: [Biomarker] = []
    /// Card size per biomarker, chosen from the card's menu. Absent
    /// means `BiomarkerTileSize.default`.
    var tileSizes: [Biomarker: BiomarkerTileSize] = [:]

    /// Canonical default config. Used by the profile decoders when
    /// the field is missing on an older profile JSON. Mirrors
    /// `Biomarker.defaultVisible` so a fresh install and an
    /// upgrading user converge on the same starting state.
    static let `default` = BiologyConfig()

    // MARK: - Mutations

    func tileSize(for biomarker: Biomarker) -> BiomarkerTileSize {
        tileSizes[biomarker] ?? .default
    }

    mutating func setTileSize(_ size: BiomarkerTileSize, for biomarker: Biomarker) {
        tileSizes[biomarker] = size == .default ? nil : size
    }

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

    /// "Available but not yet added" — catalog cases that aren't in
    /// visible or hidden. Drives the Edit
    /// sheet's third section so the user can find biomarkers they
    /// haven't surfaced before.
    var availableBiomarkers: [Biomarker] {
        let claimed = Set(visibleBiomarkers).union(hiddenBiomarkers)
        return Biomarker.allCases.filter { !claimed.contains($0) }
    }
}

extension BiologyConfig {
    private enum CodingKeys: String, CodingKey {
        case visibleBiomarkers, hiddenBiomarkers, tileSizes, hasSeenIntro
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        visibleBiomarkers = try Self.decodeBiomarkers(c, .visibleBiomarkers) ?? Biomarker.defaultVisible
        hiddenBiomarkers = try Self.decodeBiomarkers(c, .hiddenBiomarkers) ?? []
        // Keyed by raw value; unknown biomarkers or sizes are dropped.
        let rawSizes = try c.decodeIfPresent([String: String].self, forKey: .tileSizes) ?? [:]
        tileSizes = Dictionary(uniqueKeysWithValues: rawSizes.compactMap { key, value in
            guard let biomarker = Biomarker(rawValue: key), let size = BiomarkerTileSize(rawValue: value) else { return nil }
            return (biomarker, size)
        })
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(visibleBiomarkers, forKey: .visibleBiomarkers)
        try c.encode(hiddenBiomarkers, forKey: .hiddenBiomarkers)
        if !tileSizes.isEmpty {
            try c.encode(
                Dictionary(uniqueKeysWithValues: tileSizes.map { ($0.key.rawValue, $0.value.rawValue) }),
                forKey: .tileSizes
            )
        }
        // Builds before the tolerant decoder require this key; without it
        // they fail the whole ProfileExtension and save it back empty.
        try c.encode(false, forKey: .hasSeenIntro)
    }

    /// Decodes raw values and drops any this build doesn't know, so a
    /// biomarker added in a newer build can't fail the decode.
    private static func decodeBiomarkers(
        _ c: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) throws -> [Biomarker]? {
        try c.decodeIfPresent([String].self, forKey: key)?.compactMap(Biomarker.init(rawValue:))
    }
}

/// How much room a biomarker card takes on the Biology tab: half a row
/// for a glance, a full row with a sparkline, or a full row with a
/// taller chart.
enum BiomarkerTileSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large

    static let `default`: BiomarkerTileSize = .small
}

extension BiomarkerTileSize {
    /// Biomarkers laid out in rows: two small cards share a row, medium
    /// and large take one each. A small card with no partner keeps its
    /// row to itself rather than stretching.
    static func rows(for biomarkers: [Biomarker], sizes: [Biomarker: BiomarkerTileSize]) -> [[Biomarker]] {
        var rows: [[Biomarker]] = []
        var pending: Biomarker?
        for biomarker in biomarkers {
            if (sizes[biomarker] ?? .default) == .small {
                if let first = pending {
                    rows.append([first, biomarker])
                    pending = nil
                } else {
                    pending = biomarker
                }
            } else {
                if let first = pending {
                    rows.append([first])
                    pending = nil
                }
                rows.append([biomarker])
            }
        }
        if let pending { rows.append([pending]) }
        return rows
    }
}
