import Foundation
import ActivityKit
import SwiftUI

/// Roadmap v2.5.3 — Live Activity controller for in-progress dose
/// windows. Starts an activity when a scheduled dose enters its
/// "active window" (default: 30 min before doseTime → 90 min after);
/// pushes a `.completed = true` update when the user logs the dose;
/// ends the activity once the window passes or the user logs.
///
/// Lives in the iOS app target only (not the widget) since it relies
/// on `Activity<…>.request(...)` which requires app authorisation.
/// Safe to call on iOS < 16.1 — every entry-point bails early.
@MainActor
final class DoseLiveActivityService {
    static let shared = DoseLiveActivityService()

    /// Earliest the activity is started before the dose's scheduled
    /// time. 30 minutes is generous enough that morning doses surface
    /// during a coffee-and-glance moment without spamming the user
    /// with banners hours ahead.
    private static let startLeadMinutes: Int = 30
    /// Latest the activity stays alive after the scheduled time
    /// before being auto-dismissed. 90 minutes covers "took it but
    /// didn't open the app" without leaving stale activities for
    /// hours.
    private static let stalenessMinutes: Int = 90

    private init() {}

    // MARK: - Public surface

    /// Reconciles the user's open Activities against `entries`. Starts
    /// new activities for any entry currently in the active window
    /// without one, and ends activities whose entries are no longer
    /// in the window or have been deleted. Call on app foreground +
    /// after every entry mutation.
    func reconcile(entries: [ProtocolEntry]) {
        guard #available(iOS 16.1, *), areLiveActivitiesEnabled else { return }
        let now = Date()
        let inWindow = entries.filter { entry in
            isInActiveWindow(entry, at: now)
        }

        let inWindowIDs = Set(inWindow.map(\.id))
        let openActivities = Activity<DoseWindowAttributes>.activities

        // End activities whose entries are no longer in-window or
        // gone entirely.
        for activity in openActivities where !inWindowIDs.contains(activity.attributes.entryId) {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }

        // Start activities for in-window entries that don't have one
        // yet. If the user has 4+ open activities (the system soft
        // cap on most devices), skip the rest — better to leave the
        // earliest few than fail silently.
        let openIDs = Set(openActivities.map(\.attributes.entryId))
        for entry in inWindow where !openIDs.contains(entry.id) {
            startActivity(for: entry)
        }
    }

    /// Push the `completed = true` content state for the matching
    /// activity. Doesn't end immediately — the live activity briefly
    /// shows "Logged" before the next reconcile pass dismisses it.
    func markCompleted(_ entryId: UUID) {
        guard #available(iOS 16.1, *), areLiveActivitiesEnabled else { return }
        guard let activity = Activity<DoseWindowAttributes>.activities.first(where: {
            $0.attributes.entryId == entryId
        }) else { return }

        let updated = DoseWindowAttributes.ContentState(
            doseTime: activity.content.state.doseTime,
            completed: true
        )
        Task {
            await activity.update(ActivityContent(state: updated, staleDate: nil))
            // Auto-dismiss after a short confirmation window so the
            // user sees the "Logged" badge, then the lock screen
            // clears itself.
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// End every open activity. Used on logout / data reset paths.
    func endAll() {
        guard #available(iOS 16.1, *) else { return }
        for activity in Activity<DoseWindowAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    // MARK: - Internals

    @available(iOS 16.1, *)
    private var areLiveActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    @available(iOS 16.1, *)
    private func startActivity(for entry: ProtocolEntry) {
        let palette = VialPalette.colors(for: entry.peptide.name)
        let attributes = DoseWindowAttributes(
            entryId: entry.id,
            peptideAbbreviation: entry.peptide.abbreviation,
            doseDisplay: entry.dose,
            tintHex: hex(of: palette.fill)
        )
        let initialState = DoseWindowAttributes.ContentState(
            doseTime: entry.date,
            completed: entry.completed
        )
        let stale = Calendar.current.date(byAdding: .minute, value: Self.stalenessMinutes, to: entry.date)

        do {
            _ = try Activity<DoseWindowAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: initialState, staleDate: stale),
                pushType: nil
            )
        } catch {
            // Authorisation revoked, system limit hit, etc — log but
            // don't propagate. The next reconcile pass tries again.
            AppLog.live.error("Live Activity start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func isInActiveWindow(_ entry: ProtocolEntry, at now: Date) -> Bool {
        guard !entry.completed else { return false }
        let windowStart = Calendar.current.date(byAdding: .minute, value: -Self.startLeadMinutes, to: entry.date) ?? entry.date
        let windowEnd = Calendar.current.date(byAdding: .minute, value: Self.stalenessMinutes, to: entry.date) ?? entry.date
        return now >= windowStart && now <= windowEnd
    }

    /// Extracts a packed RGB UInt from a SwiftUI Color so the widget
    /// (which can't depend on VialPalette) can rebuild it. The widget
    /// only ever consumes the bytes — no further math — so this is a
    /// safe round-trip on the basic sRGB range we use.
    private func hex(of color: SwiftUI.Color) -> UInt {
        // SwiftUI.Color → CGColor for component access. Falls back to
        // the brand purple when an opaque colour can't be resolved
        // (rare; happens only in odd dark/light dynamic colour cases).
        let resolved = color.cgColor ?? CGColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 1)
        let components = resolved.components ?? [0.31, 0.27, 0.90, 1]
        let r = UInt(max(0, min(1, components.first ?? 0)) * 255)
        let g = UInt(max(0, min(1, components.dropFirst().first ?? 0)) * 255)
        let b = UInt(max(0, min(1, components.dropFirst(2).first ?? 0)) * 255)
        return (r << 16) | (g << 8) | b
    }
}

