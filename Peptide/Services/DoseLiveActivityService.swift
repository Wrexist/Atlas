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
    /// hours. Also where `DoseWindowAttributes` closes the window.
    private static let stalenessMinutes = DoseWindowAttributes.ContentState.windowCloseMinutes

    private init() {}

    // MARK: - Public surface

    /// Reconciles the user's open Activities against `entries`. Starts
    /// new activities for any entry currently in the active window
    /// without one, moves an open activity's countdown when its entry
    /// was rescheduled, and ends activities whose entries are no longer
    /// in the window, have been deleted, or had their peptide or dose
    /// edited (static attributes can't be updated, so those restart).
    /// Ending runs even with Live Activities switched off, so a card
    /// left up when the user disabled them still clears. Call on app
    /// foreground + after every entry mutation.
    func reconcile(entries: [ProtocolEntry]) {
        let now = Date()
        let inWindow = entries.filter { entry in
            Self.isInActiveWindow(entry, at: now)
        }
        let inWindowByID = Dictionary(inWindow.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var openIDs = Set<UUID>()
        for activity in Activity<DoseWindowAttributes>.activities {
            guard let entry = inWindowByID[activity.attributes.entryId],
                  Self.attributesMatch(activity.attributes, entry) else {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
                continue
            }
            openIDs.insert(entry.id)
            if activity.content.state.doseTime != entry.date {
                let state = Self.initialState(for: entry)
                Task { await activity.update(ActivityContent(state: state, staleDate: state.lateBoundary)) }
            }
        }

        // Start activities for in-window entries that don't have one
        // yet. If the user has 4+ open activities (the system soft
        // cap on most devices), skip the rest — better to leave the
        // earliest few than fail silently.
        guard areLiveActivitiesEnabled else { return }
        for entry in inWindow where !openIDs.contains(entry.id) {
            startActivity(for: entry)
        }
    }

    /// Ends the matching activity on its `completed = true` state. The
    /// system keeps the "Logged" badge up briefly, then dismisses it —
    /// no app-side timer, so it clears even if the app is suspended.
    func markCompleted(_ entryId: UUID) {
        guard areLiveActivitiesEnabled else { return }
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
        let dismissAt = Date().addingTimeInterval(DoseWindowAttributes.ContentState.loggedBadgeSeconds)
        Task {
            await activity.end(
                ActivityContent(state: updated, staleDate: nil),
                dismissalPolicy: .after(dismissAt)
            )
        }
    }

    /// End every open activity. Used on logout / data reset paths.
    func endAll() {
        for activity in Activity<DoseWindowAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    // MARK: - Internals

    private var areLiveActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private func startActivity(for entry: ProtocolEntry) {
        let palette = VialPalette.colors(for: entry.peptide.name, category: entry.peptide.category)
        let attributes = DoseWindowAttributes(
            entryId: entry.id,
            peptideAbbreviation: entry.peptide.abbreviation,
            peptideName: entry.peptide.name,
            doseDisplay: entry.dose,
            tintHex: Self.hex(of: palette.fill)
        )
        let initialState = Self.initialState(for: entry)
        do {
            _ = try Activity<DoseWindowAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: initialState, staleDate: initialState.lateBoundary),
                pushType: nil
            )
        } catch {
            // Authorisation revoked, system limit hit, etc — log but
            // don't propagate. The next reconcile pass tries again.
            AppLog.live.error("Live Activity start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func initialState(for entry: ProtocolEntry) -> DoseWindowAttributes.ContentState {
        let windowStart = Calendar.current.date(
            byAdding: .minute,
            value: -startLeadMinutes,
            to: entry.date
        ) ?? entry.date
        return DoseWindowAttributes.ContentState(
            doseTime: entry.date,
            windowStart: windowStart,
            completed: entry.completed
        )
    }

    /// Whether an open activity still describes `entry`. The tint is
    /// left out: it is derived from the peptide, and resolving it
    /// against the current trait collection could differ between
    /// passes and restart the activity for nothing.
    static func attributesMatch(_ attributes: DoseWindowAttributes, _ entry: ProtocolEntry) -> Bool {
        attributes.peptideAbbreviation == entry.peptide.abbreviation
            && attributes.peptideName == entry.peptide.name
            && attributes.doseDisplay == entry.dose
    }

    /// Pure window math — internal (not private) so the unit tests
    /// can pin the boundaries without ActivityKit in the loop.
    static func isInActiveWindow(_ entry: ProtocolEntry, at now: Date) -> Bool {
        guard !entry.completed else { return false }
        let windowStart = Calendar.current.date(byAdding: .minute, value: -startLeadMinutes, to: entry.date) ?? entry.date
        let windowEnd = Calendar.current.date(byAdding: .minute, value: stalenessMinutes, to: entry.date) ?? entry.date
        return now >= windowStart && now <= windowEnd
    }

    /// Extracts a packed RGB UInt from a SwiftUI Color so the widget
    /// (which can't depend on VialPalette) can rebuild it. The widget
    /// only ever consumes the bytes — no further math — so this is a
    /// safe round-trip on the basic sRGB range we use.
    static func hex(of color: SwiftUI.Color) -> UInt {
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

