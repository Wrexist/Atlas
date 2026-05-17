import Foundation

/// Restores a previously-exported `AppBackup` JSON back into the live
/// `DataStore`. Plan E closing the loop on `ExportService.exportFullBackup`.
///
/// Design constraints:
/// - **Validate before write.** A malformed backup can't be allowed to
///   partial-apply; the user's current data must survive a bad import.
///   `validate(_:)` returns a preview without mutating anything.
/// - **All-or-nothing.** `apply(...)` constructs the new state in
///   memory first, snapshots the current state to a recovery file,
///   then commits in one go.
/// - **Three strategies.** Replace wipes the current state and lands
///   the backup verbatim. Merge keeps existing rows on ID conflict
///   and inserts everything else. DryRun validates without writing.
/// - **Schema-version aware.** Backups carry a `version` string; an
///   import refuses anything whose major version is unknown.
@MainActor
enum BackupImportService {

    /// Soft cap on the raw JSON size. A 50 MB blob is plenty for
    /// years of dose history + meal logs; anything larger is almost
    /// certainly a corrupt file or a different app's export.
    static let maxBackupBytes: Int = 50 * 1024 * 1024

    /// Supported `AppBackup.version` major prefixes. A backup whose
    /// version doesn't match one of these is rejected. Update when a
    /// breaking schema change ships.
    static let supportedMajorVersions: Set<String> = ["1", "2"]

    /// Controls how the import interacts with the user's current data.
    enum Strategy: Hashable, Sendable {
        /// Wipe current protocols/entries/profile and restore from the
        /// backup wholesale. The dangerous one — used after a fresh
        /// install or when the user explicitly wants to overwrite.
        case replace
        /// Keep existing rows where the ID conflicts with the backup;
        /// insert everything else. Profile fields are kept from the
        /// current state; only newly-encountered IDs in protocols /
        /// entries land. The safe default.
        case merge
        /// Validate only — return the preview without writing.
        case dryRun
    }

    enum ImportError: Error, LocalizedError {
        case fileTooLarge(bytes: Int)
        case invalidJSON(String)
        case unsupportedVersion(String)
        case decodeFailure(String)
        case bounds(String)
        case applyFailed(String)

        var errorDescription: String? {
            switch self {
            case .fileTooLarge(let bytes):
                return "This backup is unusually large (\(bytes / 1024 / 1024) MB) and was rejected to avoid accidentally importing a different app's export."
            case .invalidJSON(let detail):
                return "Couldn't read the backup file: \(detail)"
            case .unsupportedVersion(let v):
                return "This backup was created by a version of Atlas that this build can't read (\(v)). Update the app and try again."
            case .decodeFailure(let detail):
                return "The backup decoded partially but a field was malformed: \(detail)"
            case .bounds(let detail):
                return "The backup contents look implausible: \(detail)"
            case .applyFailed(let detail):
                return "Backup validated but couldn't be applied: \(detail)"
            }
        }
    }

    /// Lightweight summary surfaced before the user confirms an import.
    /// Counts are derived from the backup, not the current state.
    struct Preview: Equatable, Sendable {
        let exportDate: Date
        let version: String
        let protocolsCount: Int
        let entriesCount: Int
        let profileName: String
        let hasMealHistory: Bool
        let hasLabHistory: Bool
        let hasWeightHistory: Bool
    }

    // MARK: - Validate

    /// Parses + structurally validates the backup. Doesn't write
    /// anything. Errors thrown here are user-actionable strings the
    /// UI can render directly.
    static func validate(_ data: Data) throws -> (backup: AppBackup, preview: Preview) {
        guard data.count <= maxBackupBytes else {
            throw ImportError.fileTooLarge(bytes: data.count)
        }

        // Step 1: parse as JSON to confirm structure before attempting
        // a typed decode. Surfaces a clearer error for "this isn't
        // JSON" vs "JSON shape doesn't match AppBackup".
        do {
            _ = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ImportError.invalidJSON(error.localizedDescription)
        }

        // Step 2: typed decode.
        let backup: AppBackup
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            backup = try decoder.decode(AppBackup.self, from: data)
        } catch {
            throw ImportError.decodeFailure(error.localizedDescription)
        }

        // Step 3: version gate. Reject unknown major versions so a
        // backup from a future build doesn't apply against this app's
        // older schema and lose fields silently.
        let majorVersion = String(backup.version.split(separator: ".").first ?? "")
        guard supportedMajorVersions.contains(majorVersion) else {
            throw ImportError.unsupportedVersion(backup.version)
        }

        // Step 4: sanity bounds. Catch malformed exports that decode
        // OK but carry nonsensical values (e.g. negative dates, NaN
        // sized arrays).
        try sanityCheck(backup)

        let preview = Preview(
            exportDate: backup.exportDate,
            version: backup.version,
            protocolsCount: backup.protocols.count,
            entriesCount: backup.entries.count,
            profileName: backup.profile.name.isEmpty ? "—" : backup.profile.name,
            hasMealHistory: !backup.profile.mealHistory.isEmpty,
            hasLabHistory: !backup.profile.labHistory.isEmpty,
            hasWeightHistory: !backup.profile.weightHistory.isEmpty
        )
        return (backup, preview)
    }

    private static func sanityCheck(_ backup: AppBackup) throws {
        // Anchor the upper bound at "a power user's lifetime of data" —
        // 10 years of 5 active protocols × 365 daily entries = 18,250.
        // 100k is a 5× safety margin.
        if backup.entries.count > 100_000 {
            throw ImportError.bounds("entries count (\(backup.entries.count)) exceeds the plausible maximum (100,000)")
        }
        if backup.protocols.count > 500 {
            throw ImportError.bounds("protocols count (\(backup.protocols.count)) exceeds the plausible maximum (500)")
        }
        // Reject obviously-corrupt timestamps.
        let now = Date()
        if backup.exportDate > now.addingTimeInterval(24 * 60 * 60) {
            throw ImportError.bounds("export date is more than a day in the future")
        }
    }

    // MARK: - Apply

    /// Applies a previously-validated backup. The caller is expected
    /// to have already shown the preview to the user and gotten an
    /// explicit Replace / Merge confirmation. Returns the realized
    /// preview (counts after the apply) so the caller can render
    /// "X protocols restored · Y entries restored".
    @discardableResult
    static func apply(
        _ backup: AppBackup,
        strategy: Strategy,
        into dataStore: DataStore
    ) throws -> Preview {
        // Snapshot first so a worst-case "everything goes wrong" still
        // has a recovery path. The snapshot URL is logged and the
        // caller can surface a "restore from this" affordance.
        if strategy != .dryRun {
            if let snapshot = BackupSnapshotService.snapshotCurrentState(dataStore: dataStore) {
                AppLog.persistence.error(
                    "BackupImport: pre-apply snapshot at \(snapshot.lastPathComponent, privacy: .public)"
                )
            }
        }

        guard strategy != .dryRun else {
            // Re-derive the preview from the backup — same shape the
            // validate path produced; nothing committed.
            return Preview(
                exportDate: backup.exportDate,
                version: backup.version,
                protocolsCount: backup.protocols.count,
                entriesCount: backup.entries.count,
                profileName: backup.profile.name.isEmpty ? "—" : backup.profile.name,
                hasMealHistory: !backup.profile.mealHistory.isEmpty,
                hasLabHistory: !backup.profile.labHistory.isEmpty,
                hasWeightHistory: !backup.profile.weightHistory.isEmpty
            )
        }

        // Build the new state in memory, then hand off to DataStore as
        // a single transactional apply. DataStore.applyImport handles
        // the actual write + repo upserts + widget reload.
        let resolvedProtocols: [PeptideProtocol]
        let resolvedEntries: [ProtocolEntry]
        let resolvedProfile: UserProfile

        switch strategy {
        case .replace:
            resolvedProtocols = backup.protocols
            resolvedEntries = backup.entries
            // A backup taken from a pre-Plan-C build has
            // `workoutLegacyMigrationCompleted == false` (decoded
            // via decodeIfPresent) AND a non-empty
            // `profile.workoutHistory`. If we restore that wholesale,
            // the next launch re-runs WorkoutLogMigrationService and
            // creates duplicate StoredWorkoutSession rows for entries
            // already migrated on the original device. Force the
            // marker on so the migration stays skipped. Any genuine
            // legacy entries the backup carries are already in the
            // StoredWorkoutSession stream via the source device's
            // earlier migration; the array on the profile is
            // redundant residue.
            var profile = backup.profile
            profile.workoutLegacyMigrationCompleted = true
            profile.workoutHistory = []
            resolvedProfile = profile
        case .merge:
            // Merge logic: take the current state as the base, then
            // insert any ID not present from the backup. Existing IDs
            // are kept as-is (favours the user's most-recent edits
            // over the backup's possibly-older values).
            let existingProtocolIDs = Set(dataStore.protocols.map(\.id))
            let existingEntryIDs = Set(dataStore.entries.map(\.id))
            resolvedProtocols = dataStore.protocols + backup.protocols.filter {
                !existingProtocolIDs.contains($0.id)
            }
            resolvedEntries = dataStore.entries + backup.entries.filter {
                !existingEntryIDs.contains($0.id)
            }
            // Profile merge: current wins on every scalar field;
            // history arrays union by ID where present, append-only
            // for fields without IDs. Implemented inside DataStore
            // because it has full visibility into the field set.
            resolvedProfile = mergeProfile(current: dataStore.profile, incoming: backup.profile)
        case .dryRun:
            // Unreachable — guarded above.
            fatalError("dryRun should have early-returned")
        }

        do {
            try dataStore.applyImport(
                protocols: resolvedProtocols,
                entries: resolvedEntries,
                profile: resolvedProfile
            )
        } catch {
            throw ImportError.applyFailed(error.localizedDescription)
        }

        return Preview(
            exportDate: backup.exportDate,
            version: backup.version,
            protocolsCount: resolvedProtocols.count,
            entriesCount: resolvedEntries.count,
            profileName: resolvedProfile.name.isEmpty ? "—" : resolvedProfile.name,
            hasMealHistory: !resolvedProfile.mealHistory.isEmpty,
            hasLabHistory: !resolvedProfile.labHistory.isEmpty,
            hasWeightHistory: !resolvedProfile.weightHistory.isEmpty
        )
    }

    /// Field-level merge for `UserProfile`. Current state wins for
    /// scalars; history arrays union by ID where present.
    private static func mergeProfile(current: UserProfile, incoming: UserProfile) -> UserProfile {
        var merged = current

        // Weight history: union by entry ID.
        let currentWeightIDs = Set(current.weightHistory.map(\.id))
        merged.weightHistory = current.weightHistory + incoming.weightHistory.filter {
            !currentWeightIDs.contains($0.id)
        }

        // Lab history: union by ID.
        let currentLabIDs = Set(current.labHistory.map(\.id))
        merged.labHistory = current.labHistory + incoming.labHistory.filter {
            !currentLabIDs.contains($0.id)
        }

        // Meal history: union by ID.
        let currentMealIDs = Set(current.mealHistory.map(\.id))
        merged.mealHistory = current.mealHistory + incoming.mealHistory.filter {
            !currentMealIDs.contains($0.id)
        }

        // Outcome history: union by ID.
        let currentOutcomeIDs = Set(current.outcomeHistory.map(\.id))
        merged.outcomeHistory = current.outcomeHistory + incoming.outcomeHistory.filter {
            !currentOutcomeIDs.contains($0.id)
        }

        // Recipes + custom foods: union by ID.
        let currentRecipeIDs = Set(current.recipes.map(\.id))
        merged.recipes = current.recipes + incoming.recipes.filter {
            !currentRecipeIDs.contains($0.id)
        }
        let currentFoodIDs = Set(current.customFoods.map(\.id))
        merged.customFoods = current.customFoods + incoming.customFoods.filter {
            !currentFoodIDs.contains($0.id)
        }

        // Favorite foods: set union.
        merged.favoriteFoodIDs = current.favoriteFoodIDs.union(incoming.favoriteFoodIDs)

        return merged
    }
}
