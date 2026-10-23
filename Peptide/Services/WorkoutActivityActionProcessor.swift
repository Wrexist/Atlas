import Foundation

/// Applies taps queued by the workout Live Activity's button. Taps for
/// a workout that has since finished or been replaced are dropped.
@MainActor
enum WorkoutActivityActionProcessor {
    static func drain() {
        let queued = PendingWorkoutActionStore.drain()
        // Touch the service only when there is work, so the launch-time
        // drain doesn't load the workout store for nothing.
        guard !queued.isEmpty else { return }
        let service = WorkoutSessionService.shared
        for pending in queued {
            guard service.activeSession?.id == pending.sessionId else { continue }
            switch pending.action {
            case .skipRest:
                // A tap drained late must not cancel a newer rest that a
                // later set started, same as the Watch's skip.
                if service.activeSession?.restWasRunning(at: pending.tappedAt) == true { service.skipRest() }
            case .completeSet: service.completeNextSet(now: pending.tappedAt)
            }
        }
    }

    /// Drains the moment a tap is queued while the app process is alive,
    /// including when iOS launches it in the background to run the
    /// intent. Caller retains the token for the process lifetime.
    static func startObserving() -> PendingDoseLogProcessor.ObservationToken {
        let token = PendingDoseLogProcessor.ObservationToken()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(token).toOpaque(),
            { _, _, _, _, _ in
                Task { @MainActor in WorkoutActivityActionProcessor.drain() }
            },
            CrossProcessNotification.pendingWorkoutActionQueued as CFString,
            nil,
            .deliverImmediately
        )
        return token
    }
}
