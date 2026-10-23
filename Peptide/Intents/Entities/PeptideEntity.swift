import AppIntents

/// Lightweight projection of `Peptide` for the App Intents subsystem.
/// Surfaces every peptide the user has at least one active protocol
/// for so Siri / Shortcuts can resolve phrases like "Log my BPC-157"
/// against a real entity instead of a free-text guess.
///
/// Mirrors only the fields the intent layer needs (id, display name,
/// abbreviation) — the full `Peptide` model carries lots of data
/// (default doses, frequency, route) that doesn't belong on the Siri
/// surface. Keeping the projection narrow also makes the query path
/// cheap on a cold launch.
struct PeptideEntity: AppEntity, Identifiable {
    let id: String
    let displayName: String
    let abbreviation: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: LocalizedStringResource("Peptide", comment: "App Intents — type name for one peptide entity"),
            numericFormat: LocalizedStringResource("\(placeholder: .int) peptides")
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(displayName)",
            subtitle: "\(abbreviation)"
        )
    }

    // Stateless query — `let` so the shared instance is immutable
    // and Swift 6 strict concurrency accepts it as Sendable shared
    // state.
    static let defaultQuery = PeptideEntityQuery()
}

/// Powers the parameter picker in Shortcuts ("which peptide?"),
/// Siri's name resolution ("log BPC-157" → match by name OR
/// abbreviation), and the suggested-entities row that appears under
/// the parameter field. We feed it the user's *active* protocols
/// only — paused / completed peptides aren't valid log targets.
struct PeptideEntityQuery: EntityQuery {

    func entities(for identifiers: [String]) async throws -> [PeptideEntity] {
        // One hop — both helpers are @MainActor, so they share a
        // single run block instead of two serial waits on main.
        let all = await MainActor.run { Self.allEntities(in: IntentDataStore.resolve()) }
        let lookup = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return identifiers.compactMap { lookup[$0] }
    }

    func suggestedEntities() async throws -> [PeptideEntity] {
        return await MainActor.run { Self.allEntities(in: IntentDataStore.resolve()) }
    }

    /// String-search resolver. Siri's NL pipeline calls this when the
    /// user says "BPC" — we match name OR abbreviation.
    func entities(matching string: String) async throws -> [PeptideEntity] {
        let all = await MainActor.run { Self.allEntities(in: IntentDataStore.resolve()) }
        return all.filter { Self.matches($0, query: string) }
    }

    /// Siri transcribes "BPC-157" as "BPC 157" or "BPC157", neither a
    /// substring of the name as written, so both sides are compared with
    /// case, accents, spaces and punctuation removed.
    static func matches(_ entity: PeptideEntity, query: String) -> Bool {
        let needle = searchKey(query)
        guard !needle.isEmpty else { return false }
        return searchKey(entity.displayName).contains(needle)
            || searchKey(entity.abbreviation).contains(needle)
    }

    private static func searchKey(_ text: String) -> String {
        FoodLibraryLogic.normalized(text).replacingOccurrences(of: " ", with: "")
    }

    /// Walks the live protocol list, deduplicates by peptide id, and
    /// projects into the entity shape. Runs on MainActor because
    /// `DataStore.activeProtocols` reads observation-tracked state.
    @MainActor
    private static func allEntities(in store: DataStore) -> [PeptideEntity] {
        var seen: Set<UUID> = []
        var out: [PeptideEntity] = []
        for proto in store.activeProtocols {
            for peptide in proto.peptides where !seen.contains(peptide.id) {
                seen.insert(peptide.id)
                out.append(PeptideEntity(
                    id: peptide.id.uuidString,
                    displayName: peptide.name,
                    abbreviation: peptide.abbreviation
                ))
            }
        }
        return out.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}
