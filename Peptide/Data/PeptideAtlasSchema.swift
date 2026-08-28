import Foundation
import SwiftData

/// Current SwiftData schema. Declares every `@Model` type Atlas
/// persists, version-tagged for explicit migration support.
///
/// Plan D scaffold: the schema is currently versioned at V2 because
/// batch 5 retroactively removed `@Attribute(.unique)` from
/// `StoredProtocol`, `StoredEntry`, and the four training types
/// (CloudKit doesn't support unique constraints; the attribute was
/// silently disabling iCloud sync for every user). That structural
/// change has already landed transparently for existing users via
/// Apple's inferred migration. The V2 declaration here makes the
/// current state explicit so a future schema change (V3) can
/// declare a real `MigrationStage` for the V2→V3 transition with
/// confidence in the starting point.
///
/// Adding a new `@Model` type:
///   1. Define the type as usual.
///   2. Append `YourNewModel.self` to `PeptideAtlasSchemaV2.models`.
///   3. If the field set changes after release, bump to V3 — define
///      `PeptideAtlasSchemaV3` and a `MigrationStage` in
///      `PeptideAtlasMigrationPlan.stages`.
enum PeptideAtlasSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            StoredProtocol.self,
            StoredEntry.self,
            StoredProfile.self,
            StoredWorkoutSession.self,
            StoredCustomExercise.self,
            StoredRoutine.self,
            StoredPersonalRecord.self,
        ]
    }
}

// NOTE on the profile column split (Data Integrity 04): `StoredProfile`
// gained additive optional/defaulted columns (mealsData … summariesData,
// singletonKey, updatedAt) WITHOUT a version bump. A declared V3 whose
// model list shares the same live `@Model` classes as V2 makes SwiftData
// compute two version checksums from one editable model and abort at
// container creation ("Attempting to retrieve an NSManagedObjectModel
// version checksum while the model is still editable" → signal abrt in
// CI run 416). Additive optional columns ride Apple's inferred
// lightweight migration instead — the same path the `.unique` removal
// and the original `extensionData` column shipped through. Bump to V3
// only for a structural change, and then with distinct model types per
// version, not shared classes.

/// Migration plan for the SwiftData store. Today this is single-stage
/// (V2 only) because the V1→V2 transition predates this scaffold —
/// every running install is already at V2 via Apple's inferred
/// migration on the `@Attribute(.unique)` removal.
///
/// When a future change requires a real migration:
///   1. Define `PeptideAtlasSchemaV3` with the new shape.
///   2. Append `PeptideAtlasSchemaV3.self` to `schemas`.
///   3. Append a `MigrationStage` to `stages`:
///        - `.lightweight(fromVersion:toVersion:)` for purely additive
///          changes (new optional fields, new entities).
///        - `.custom(fromVersion:toVersion:willMigrate:didMigrate:)`
///          for any structural change — renames, type changes,
///          required-field additions, computed-from-old data fills.
///   4. Update `PeptideAtlasSchemaV2` to remain referenceable; do
///      NOT delete V2 even after V3 ships — the migration stage
///      needs both endpoints declared.
enum PeptideAtlasMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PeptideAtlasSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        []  // No staged migrations; additive column changes are inferred.
    }
}
