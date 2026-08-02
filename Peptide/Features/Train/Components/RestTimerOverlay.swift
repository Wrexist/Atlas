import Combine
import SwiftUI
import UserNotifications

/// In-workout rest countdown. Surfaces above the keyboard with a
/// circular progress ring + remaining-time label and three actions:
/// Skip (dismiss the timer immediately), -15s / +15s (adjust the
/// remaining time), End (full skip).
///
/// Mounted on ActiveWorkoutView via .overlay and shown only when
/// `state.isRunning`. The countdown is driven by a `Timer.publish`
/// every 100ms — fine-grained enough for a smooth ring sweep without
/// burning the publisher needlessly. When the app backgrounds, the
/// timer fires a local notification at the original target time so
/// the user knows when to lift; foreground resume reads
/// `state.targetEnd` and recomputes remaining seconds rather than
/// trusting the ticks alone (audit Train H2).
struct RestTimerOverlay: View {
    @Binding var state: RestTimerState

    /// Connected on appear and cancelled on disappear. `.autoconnect()`
    /// starts the publisher the moment the view value is *created*, which
    /// for an `.overlay` on ActiveWorkoutView means 10 ticks a second for
    /// the whole workout — including the long stretches between sets when
    /// no timer is running and nothing consumes them.
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common)
    @State private var connection: (any Cancellable)?

    var body: some View {
        if state.isRunning {
            content
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.lg)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onReceive(timer) { _ in tick() }
                .onAppear { connection = timer.connect() }
                .onDisappear {
                    connection?.cancel()
                    connection = nil
                }
        }
    }

    private var content: some View {
        HStack(spacing: Spacing.md) {
            ring
            VStack(alignment: .leading, spacing: 2) {
                Text("Rest")
                    .font(AppFont.scaled(10, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(AppColor.textTertiary)
                Text(remainingLabel)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            controls
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceElevated.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .stroke(AppColor.accentPrimary.opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 16, y: 6)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(AppColor.textTertiary.opacity(0.2), lineWidth: 4)
                .frame(width: 44, height: 44)
            Circle()
                .trim(from: 0, to: state.fraction)
                .stroke(AppColor.accentPrimary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 44, height: 44)
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            tinyButton(label: "−15", action: { adjust(by: -15) })
            tinyButton(label: "+15", action: { adjust(by: 15) })
            Button(action: end) {
                Text("End")
                    .font(AppFont.footnote.weight(.semibold))
                    .foregroundStyle(AppColor.background)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(AppColor.textPrimary))
            }
            .buttonStyle(.plain)
        }
    }

    private func tinyButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(AppFont.scaled(13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(AppColor.surfaceSecondary.opacity(0.8))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Time math

    private var remainingLabel: String {
        let s = max(0, Int(ceil(state.remainingSeconds)))
        let m = s / 60
        let r = s % 60
        return m > 0 ? String(format: "%d:%02d", m, r) : "0:\(String(format: "%02d", r))"
    }

    private func tick() {
        guard state.isRunning, let targetEnd = state.targetEnd else { return }
        let now = Date()
        if now >= targetEnd {
            state.completeNow()
            // Haptic when the timer hits zero — the user typically
            // isn't looking at the screen at the end of a rest.
            Haptics.success()
        }
    }

    private func adjust(by seconds: Int) {
        state.adjustRemaining(by: TimeInterval(seconds))
        Haptics.impact(.soft)
    }

    private func end() {
        state.cancel()
        Haptics.impact(.light)
    }
}

/// Drives the rest timer. Held by `ActiveWorkoutView` as @State so
/// the overlay can read + write through a binding. Resilient to
/// scenePhase transitions because `targetEnd` is an absolute Date
/// — the foreground resume path recomputes remaining seconds from
/// the wall clock rather than trusting tick counts.
struct RestTimerState: Equatable, Sendable {
    /// When set, the timer is counting toward this absolute moment.
    /// Nil means "not currently resting".
    var targetEnd: Date?
    /// The original target seconds — used to compute the ring's
    /// fraction without drifting as the user hits +15 / -15.
    var totalSeconds: TimeInterval
    /// Identifier used to cancel the matching local notification when
    /// the user ends the timer early or completes naturally.
    private(set) var notificationID: String?

    static let inactive = RestTimerState(targetEnd: nil, totalSeconds: 0)

    var isRunning: Bool { targetEnd != nil }

    var remainingSeconds: TimeInterval {
        guard let targetEnd else { return 0 }
        return max(0, targetEnd.timeIntervalSinceNow)
    }

    var fraction: CGFloat {
        guard totalSeconds > 0, isRunning else { return 0 }
        let elapsed = totalSeconds - remainingSeconds
        return CGFloat(min(1.0, max(0.0, elapsed / totalSeconds)))
    }

    /// Start a fresh rest from now for `seconds`. Caller passes the
    /// per-exercise restSeconds (or the user's default). Schedules a
    /// background notification so the user gets a buzz even if the
    /// app is in their pocket.
    mutating func start(seconds: Int) {
        let now = Date()
        let end = now.addingTimeInterval(TimeInterval(seconds))
        let id = UUID().uuidString
        targetEnd = end
        totalSeconds = TimeInterval(seconds)
        notificationID = id

        let content = UNMutableNotificationContent()
        content.title = "Time to lift"
        content.body = "Rest's up — back to it."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, TimeInterval(seconds)),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in /* best effort */ }
    }

    /// Cancel — used by the End button and on auto-complete. Cancels
    /// the local notification too so the user doesn't get a "rest's
    /// up" buzz seconds after they've already started the next set.
    mutating func cancel() {
        if let id = notificationID {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        }
        targetEnd = nil
        notificationID = nil
    }

    /// Auto-complete branch — same as cancel but skips the
    /// notification removal because the trigger already fired (the
    /// user got the buzz in-app via the haptic).
    mutating func completeNow() {
        if let id = notificationID {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        }
        targetEnd = nil
        notificationID = nil
    }

    /// Skew the timer by ± seconds. Re-schedules the notification so
    /// the buzz lands at the new target time.
    mutating func adjustRemaining(by seconds: TimeInterval) {
        guard let current = targetEnd else { return }
        let newEnd = current.addingTimeInterval(seconds)
        let now = Date()
        // Never go below 1s — UNTimeIntervalNotificationTrigger requires > 0.
        let adjustedRemaining = max(1, newEnd.timeIntervalSince(now))
        targetEnd = now.addingTimeInterval(adjustedRemaining)
        // Re-issue the notification with the new target time.
        if let id = notificationID {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        }
        let id = UUID().uuidString
        notificationID = id
        let content = UNMutableNotificationContent()
        content.title = "Time to lift"
        content.body = "Rest's up — back to it."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: adjustedRemaining,
            repeats: false
        )
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in /* best effort */ }
    }
}
