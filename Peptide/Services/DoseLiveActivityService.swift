import Foundation
import ActivityKit
import SwiftUI
import UIKit

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

    /// In-flight "show Logged for 4s then end" tasks, keyed by entry id.
    /// Tracked so a subsequent `reconcile` / `endAll` / repeat
    /// `markCompleted` can cancel a stale closer instead of letting two
    /// `activity.end(...)` calls race.
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    /// Identity token for the current dismiss task per entry. A task
    /// re-checks its token after the 4s sleep before calling `end()`:
    /// once past the sleep, `cancel()` is a no-op, so a `reconcile` or
    /// a repeat `markCompleted` would otherwise race a second `end()`.
    private var dismissTokens: [UUID: UUID] = [:]

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
        // gone entirely. Cancel any pending dismiss-after-Logged task —
        // it would call end() a second time once it wakes up.
        for activity in openActivities where !inWindowIDs.contains(activity.attributes.entryId) {
            let entryId = activity.attributes.entryId
            dismissTasks.removeValue(forKey: entryId)?.cancel()
            // Invalidate the token so a dismiss task already past its
            // sleep bows out instead of racing this end().
            dismissTokens.removeValue(forKey: entryId)
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

        let currentState = activity.content.state
        // Preserve a loggedAt set by the widget intent if one is
        // already on the state — that timestamp is closer to the
        // user's actual tap than the app's wake time.
        let updated = DoseWindowAttributes.ContentState(
            doseTime: currentState.doseTime,
            windowStart: currentState.windowStart,
            completed: true,
            loggedAt: currentState.loggedAt ?? Date()
        )
        // Cancel any prior dismiss-after-Logged task for this entry so
        // we don't double-end, and mint a fresh identity token.
        dismissTasks.removeValue(forKey: entryId)?.cancel()
        let token = UUID()
        dismissTokens[entryId] = token
        dismissTasks[entryId] = Task { [weak self] in
            await activity.update(ActivityContent(state: updated, staleDate: nil))
            // Auto-dismiss after a short confirmation window so the
            // user sees the "Logged" badge, then the lock screen
            // clears itself.
            do {
                try await Task.sleep(nanoseconds: 4_000_000_000)
            } catch {
                return // cancelled — leave the activity for reconcile to clean up
            }
            // Past the sleep, cancel() is a no-op — re-check that this
            // task is still the current one before ending the activity
            // so a superseding markCompleted / reconcile doesn't race
            // a second end().
            guard await self?.dismissTokens[entryId] == token else { return }
            await activity.end(nil, dismissalPolicy: .immediate)
            await MainActor.run {
                self?.dismissTasks.removeValue(forKey: entryId)
                self?.dismissTokens.removeValue(forKey: entryId)
                return ()
            }
        }
    }

    /// End every open activity. Used on logout / data reset paths.
    func endAll() {
        guard #available(iOS 16.1, *) else { return }
        dismissTasks.values.forEach { $0.cancel() }
        dismissTasks.removeAll()
        dismissTokens.removeAll()
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
        let palette = VialPalette.colors(for: entry.peptide.name, category: entry.peptide.category)
        let attributes = DoseWindowAttributes(
            entryId: entry.id,
            peptideAbbreviation: entry.peptide.abbreviation,
            peptideName: entry.peptide.name,
            doseDisplay: entry.dose,
            tintHex: hex(of: palette.fill)
        )
        let windowStart = Calendar.current.date(
            byAdding: .minute,
            value: -Self.startLeadMinutes,
            to: entry.date
        ) ?? entry.date
        let initialState = DoseWindowAttributes.ContentState(
            doseTime: entry.date,
            windowStart: windowStart,
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
        // SwiftUI.Color.cgColor returns nil for asset-catalog colors
        // and any color resolved through a dynamic trait — including
        // most of the brand palette that `VialPalette` may return.
        // Resolve through `UIColor` first so an asset-catalog color
        // gets concretely sampled against the current trait
        // collection. Falls back to the brand purple if even that
        // path fails (e.g. an invalid color in a preview).
        let uiColor = UIColor(color).resolvedColor(with: .current)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let ok = uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        if !ok {
            // Non-RGB color space (extremely rare for asset entries) —
            // fall back to brand purple rather than mis-sampling.
            r = 0.31; g = 0.27; b = 0.90
        }
        let rByte = UInt(max(0, min(1, r)) * 255)
        let gByte = UInt(max(0, min(1, g)) * 255)
        let bByte = UInt(max(0, min(1, b)) * 255)
        return (rByte << 16) | (gByte << 8) | bByte
    }
}

