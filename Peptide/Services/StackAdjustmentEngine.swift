import Foundation

/// Pure logic that powers the "Adjust Stack" preview surfaced from compounding alerts.
/// Computes peptide diffs and finds where dropped peptides could land instead of being discarded.
enum StackAdjustmentEngine {

    // MARK: - Title parsing

    /// Pulls the canonical key out of a `Compounding "<key>" risk` warning title.
    /// Returns nil for non-compounding warnings (the caller falls back to a generic suggestion).
    static func sideEffectKey(from warningTitle: String) -> String? {
        guard let start = warningTitle.firstIndex(of: "\"") else { return nil }
        let afterStart = warningTitle.index(after: start)
        guard afterStart < warningTitle.endIndex,
              let end = warningTitle[afterStart...].firstIndex(of: "\"") else { return nil }
        let key = warningTitle[afterStart..<end]
        return key.isEmpty ? nil : String(key)
    }

    // MARK: - Source stack resolution

    /// Active protocols that hold at least one of the affected peptides, ordered by overlap count
    /// (most-affected first). Used so the user can pick which stack to adjust when an alert spans
    /// multiple protocols.
    static func candidateProtocols(
        affectedAbbreviations: [String],
        in protocols: [PeptideProtocol]
    ) -> [PeptideProtocol] {
        let affected = Set(affectedAbbreviations)
        return protocols
            .compactMap { proto -> (PeptideProtocol, Int)? in
                let hits = proto.peptides.filter { affected.contains($0.abbreviation) }.count
                return hits > 0 ? (proto, hits) : nil
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    // MARK: - Diff

    struct Diff: Equatable {
        let added: [Peptide]
        let removed: [Peptide]
        let unchanged: [Peptide]

        var hasChanges: Bool { !added.isEmpty || !removed.isEmpty }

        var summary: String {
            switch (added.count, removed.count) {
            case (0, 0): return "No changes yet"
            case (let a, 0): return "Adding \(a)"
            case (0, let r): return "Removing \(r)"
            case (let a, let r): return "Adding \(a), removing \(r)"
            }
        }
    }

    static func diff(original: [Peptide], proposed: [Peptide]) -> Diff {
        let originalIds = Set(original.map(\.id))
        let proposedIds = Set(proposed.map(\.id))
        return Diff(
            added: proposed.filter { !originalIds.contains($0.id) },
            removed: original.filter { !proposedIds.contains($0.id) },
            unchanged: original.filter { proposedIds.contains($0.id) }
        )
    }

    // MARK: - Relocation suggestions

    enum RelocationOption: Hashable, Identifiable {
        case discard
        case moveTo(protocolId: UUID, name: String, reason: String)
        case createStack(reason: String)

        var id: String {
            switch self {
            case .discard: return "discard"
            case .moveTo(let id, _, _): return "move-\(id.uuidString)"
            case .createStack: return "new"
            }
        }

        var label: String {
            switch self {
            case .discard: return "Discard"
            case .moveTo(_, let name, _): return "Move to \(name)"
            case .createStack: return "Create new stack"
            }
        }

        var subtitle: String? {
            switch self {
            case .discard: return nil
            case .moveTo(_, _, let reason): return reason
            case .createStack(let reason): return reason
            }
        }
    }

    struct Relocation: Identifiable {
        let id = UUID()
        let peptide: Peptide
        let options: [RelocationOption]

        /// Best non-discard option (used as the sensible default).
        var recommended: RelocationOption {
            options.first { option in
                if case .discard = option { return false }
                return true
            } ?? .discard
        }
    }

    /// For each removed peptide, surface a ranked set of homes:
    ///   1. existing active protocols that won't trigger the same compounding pattern,
    ///   2. a fresh stack as a safety net,
    ///   3. always offer "discard" so users can decline.
    static func relocations(
        for removedPeptides: [Peptide],
        sourceProtocolId: UUID,
        sideEffectKey: String?,
        in protocols: [PeptideProtocol]
    ) -> [Relocation] {
        guard !removedPeptides.isEmpty else { return [] }
        let key = sideEffectKey?.lowercased()

        return removedPeptides.map { peptide in
            var options: [RelocationOption] = []

            for proto in protocols where proto.id != sourceProtocolId && proto.status == .active {
                guard !proto.peptides.contains(where: { $0.id == peptide.id }) else { continue }
                guard let reason = fitReason(for: peptide, joining: proto, sideEffectKey: key) else { continue }
                options.append(.moveTo(protocolId: proto.id, name: proto.name, reason: reason))
            }

            let newStackReason: String
            if let key, peptideHasEffect(peptide, key: key) {
                newStackReason = "Isolate \(peptide.abbreviation) from the \"\(key)\" cluster"
            } else {
                newStackReason = "Solo cycle for \(peptide.abbreviation)"
            }
            options.append(.createStack(reason: newStackReason))
            options.append(.discard)

            return Relocation(peptide: peptide, options: options)
        }
    }

    // MARK: - Fit checks

    /// Returns a reason string when `peptide` would land cleanly in `proto`, or nil if joining would
    /// recreate the same compounding cluster the user is trying to escape.
    private static func fitReason(
        for peptide: Peptide,
        joining proto: PeptideProtocol,
        sideEffectKey key: String?
    ) -> String? {
        guard let key else {
            return "Open spot in \(proto.name)"
        }

        let peptideMatches = peptideHasEffect(peptide, key: key)
        guard peptideMatches else {
            return "No \"\(key)\" overlap in \(proto.name)"
        }

        let existingMatches = proto.peptides.filter { peptideHasEffect($0, key: key) }.count
        // Compounding warnings fire at 3+ shared. Reject moves that would push the destination over.
        guard existingMatches < 2 else { return nil }
        return "Lower \"\(key)\" overlap in \(proto.name)"
    }

    private static func peptideHasEffect(_ peptide: Peptide, key: String) -> Bool {
        peptide.sideEffects.contains { $0.lowercased().contains(key) }
    }
}
