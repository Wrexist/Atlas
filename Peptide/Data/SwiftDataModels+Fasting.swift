import Foundation
import SwiftData

// MARK: - StoredFast

/// On-disk shell for a `FastSession`. Flat scalar columns — a fast has
/// no nested data worth a JSON blob.
@Model
final class StoredFast {
    // CloudKit-backed stores need no `@Attribute(.unique)` and every
    // attribute optional-or-defaulted. Uniqueness is enforced by the
    // fetch-then-insert-or-update in `SwiftDataRepository.upsertFast`.
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date?
    var targetHours: Double = 16
    /// `FastingProtocol.rawValue`; unknown values read back as `.custom`.
    var planRaw: String = FastingProtocol.sixteen.rawValue
    var remindsAtEnd: Bool = false

    init(
        id: UUID,
        startedAt: Date,
        endedAt: Date?,
        targetHours: Double,
        planRaw: String,
        remindsAtEnd: Bool
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.targetHours = targetHours
        self.planRaw = planRaw
        self.remindsAtEnd = remindsAtEnd
    }

    static func make(from fast: FastSession) -> StoredFast {
        StoredFast(
            id: fast.id,
            startedAt: fast.startedAt,
            endedAt: fast.endedAt,
            targetHours: fast.targetHours,
            planRaw: fast.plan.rawValue,
            remindsAtEnd: fast.remindsAtEnd
        )
    }

    func update(from fast: FastSession) {
        startedAt = fast.startedAt
        endedAt = fast.endedAt
        targetHours = fast.targetHours
        planRaw = fast.plan.rawValue
        remindsAtEnd = fast.remindsAtEnd
    }

    func toFastSession() -> FastSession {
        FastSession(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            targetHours: targetHours,
            plan: FastingProtocol(storedRaw: planRaw),
            remindsAtEnd: remindsAtEnd
        )
    }
}
