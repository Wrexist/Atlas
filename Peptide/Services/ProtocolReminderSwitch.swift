import Foundation

/// What flipping the protocol-reminders switch does, wherever the switch
/// lives. Settings and the profile sheet once wrote the same flag with
/// different behavior: one asked for permission and scheduled, the other
/// only saved, so reminders did not change until the next app launch.
@MainActor
enum ProtocolReminderSwitch {
    enum Outcome: Equatable {
        case scheduled, denied, cancelled
    }

    struct Effects {
        var requestAuthorization: @MainActor () async -> Bool
        var schedule: @MainActor () -> Void
        var cancel: @MainActor () -> Void
    }

    static func apply(enabled: Bool, effects: Effects) async -> Outcome {
        guard enabled else {
            effects.cancel()
            return .cancelled
        }
        guard await effects.requestAuthorization() else { return .denied }
        effects.schedule()
        return .scheduled
    }
}
