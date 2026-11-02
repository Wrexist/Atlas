import AppIntents
import Foundation

/// "Start my fast" — opens a fast with the plan, length and end reminder
/// the user last fasted with, exactly like the Meals card's Start button.
/// Never replaces a fast that's already running.
struct StartFastIntent: AppIntent {
    static let title: LocalizedStringResource = "Start fast"

    static let description = IntentDescription(
        "Starts a fast with the plan you last used. Does nothing if a fast is already running.",
        categoryName: "Fasting"
    )

    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = FastingStore.shared
        // A cold launch for the intent hasn't loaded the history yet.
        store.load()

        switch FastingIntentEngine.startDecision(active: store.active) {
        case .alreadyFasting(let since):
            let elapsed = FastingIntentEngine.spokenDuration(Date().timeIntervalSince(since))
            return .result(dialog: IntentDialog(
                LocalizedStringResource(
                    "You're already fasting — \(elapsed) so far.",
                    comment: "Siri response to “Start fast” when a fast is already running. The value is the time fasted, e.g. “3 hours, 12 minutes”."
                )
            ))
        case .start:
            let last = store.lastPlan
            let fast = store.start(
                plan: last.plan,
                targetHours: last.hours,
                remindsAtEnd: store.sessions.first?.remindsAtEnd ?? false
            )
            let hours = Int(fast.targetHours)
            let goal = fast.targetEnd.formatted(date: .omitted, time: .shortened)
            return .result(dialog: IntentDialog(
                LocalizedStringResource(
                    "Started a \(hours)-hour fast. You'll reach your goal at \(goal).",
                    comment: "Siri confirmation after starting a fast. Values: target length in hours, clock time the goal is reached."
                )
            ))
        }
    }
}

/// "End my fast" — closes the running fast now. Siri doesn't ask to
/// confirm an early end the way the Meals card does: saying it is the
/// confirmation.
struct EndFastIntent: AppIntent {
    static let title: LocalizedStringResource = "End fast"

    static let description = IntentDescription(
        "Ends the fast that's running and tells you how long it lasted.",
        categoryName: "Fasting"
    )

    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = FastingStore.shared
        store.load()
        let now = Date()

        switch FastingIntentEngine.endDecision(active: store.active, at: now) {
        case .notFasting:
            return .result(dialog: IntentDialog(
                LocalizedStringResource(
                    "You don't have a fast running.",
                    comment: "Siri response to “End fast” when no fast is open."
                )
            ))
        case .end(let elapsed, let reachedGoal, let targetHours):
            store.end(at: now)
            let duration = FastingIntentEngine.spokenDuration(elapsed)
            guard reachedGoal else {
                return .result(dialog: IntentDialog(
                    LocalizedStringResource(
                        "Fast ended after \(duration).",
                        comment: "Siri confirmation after ending a fast before its goal. The value is its length, e.g. “14 hours, 5 minutes”."
                    )
                ))
            }
            return .result(dialog: IntentDialog(
                LocalizedStringResource(
                    "Fast ended after \(duration). You reached your \(targetHours)-hour goal.",
                    comment: "Siri confirmation after ending a fast that reached its goal. Values: its length, the goal in hours."
                )
            ))
        }
    }
}

/// The decisions behind the fasting intents, kept free of App Intents
/// and SwiftData so they can be tested directly.
enum FastingIntentEngine {
    enum StartDecision: Equatable {
        case start
        case alreadyFasting(since: Date)
    }

    enum EndDecision: Equatable {
        case notFasting
        case end(elapsed: TimeInterval, reachedGoal: Bool, targetHours: Int)
    }

    static func startDecision(active: FastSession?) -> StartDecision {
        guard let active else { return .start }
        return .alreadyFasting(since: active.startedAt)
    }

    static func endDecision(active: FastSession?, at now: Date) -> EndDecision {
        guard let active else { return .notFasting }
        return .end(
            elapsed: FastingEngine.elapsed(active, at: now),
            reachedGoal: FastingEngine.remaining(active, at: now) == 0,
            targetHours: Int(active.targetHours)
        )
    }

    /// "3 hours, 12 minutes" — read aloud, where `FastingEngine.clock`'s
    /// "3:12" would sound like a time of day.
    static func spokenDuration(_ interval: TimeInterval) -> String {
        Duration.seconds(Int(max(0, interval)) / 60 * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }
}
