import SwiftData
import XCTest
@testable import Peptide

/// Regression guards for the CloudKit schema failure class (audit
/// Data Integrity 04, Phase 10): CloudKit rejects `@Attribute(.unique)`
/// and silently disabled sync for every user when the training models
/// shipped with unique constraints. These tests pin the schema-level
/// invariants that can be checked off-device; the sync behaviour itself
/// is hardware-only (docs/CLOUDKIT_HARDWARE_TEST_PLAN.md).
@MainActor
final class CloudKitSchemaCompatibilityTests: XCTestCase {

    func test_schema_hasNoUniqueAttributes() {
        let schema = Schema(versionedSchema: PeptideAtlasSchemaV3.self)
        for entity in schema.entities {
            for attribute in entity.attributes {
                XCTAssertFalse(
                    attribute.isUnique,
                    "\(entity.name).\(attribute.name) is unique — CloudKit rejects unique constraints and sync would silently stop"
                )
            }
        }
    }

    func test_schema_declaresEveryStoredModel() {
        let schema = Schema(versionedSchema: PeptideAtlasSchemaV3.self)
        let names = Set(schema.entities.map(\.name))
        for expected in ["StoredProtocol", "StoredEntry", "StoredProfile",
                         "StoredWorkoutSession", "StoredCustomExercise",
                         "StoredRoutine", "StoredPersonalRecord"] {
            XCTAssertTrue(names.contains(expected),
                          "\(expected) missing from the versioned schema — its data would stop persisting")
        }
    }

    func test_modelContainer_initializesWithMigrationPlan() throws {
        // The exact container shape `configureForTesting` and the
        // production fallback share: versioned schema + migration plan.
        // A migration-plan mistake (missing stage, bad version chain)
        // fails right here rather than at first customer launch.
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        XCTAssertNoThrow(
            try ModelContainer(
                for: Schema(versionedSchema: PeptideAtlasSchemaV3.self),
                migrationPlan: PeptideAtlasMigrationPlan.self,
                configurations: config
            )
        )
    }

    func test_migrationPlan_versionChainIsOrderedAndComplete() {
        let versions = PeptideAtlasMigrationPlan.schemas.map { $0.versionIdentifier }
        XCTAssertEqual(versions.count, Set(versions).count, "Duplicate schema versions in the plan")
        XCTAssertEqual(
            PeptideAtlasMigrationPlan.schemas.last?.versionIdentifier,
            PeptideAtlasSchemaV3.versionIdentifier,
            "The live schema must be the last link in the migration chain"
        )
    }
}
