import SwiftUI

enum AppTab: String, CaseIterable {
    /// Daily action hub — doses, meals, check-in. Was `.home`
    /// (renamed in Phase 32 to be verb-forward). `selectedTab`
    /// isn't currently persisted across launches, so no
    /// migration of the prior raw value is required.
    case today
    /// Workout planning + logging. Added in the training pivot —
    /// raw value is new so older builds that don't know about it
    /// simply fall back to `.today` when their persisted state
    /// reloads.
    case train
    /// Meal logging + macros + recipes. Promoted out of the Home
    /// section in the training pivot so food gets its own
    /// top-level surface alongside training.
    case meals
    /// Peptide reference + AI research. Was `.database`. Now also
    /// hosts the Protocols list (folded in during the training
    /// pivot — Protocols lost its dedicated tab slot to make
    /// room for Train + Meals).
    case library
    /// Stays in the enum for deep-link compatibility — the
    /// case isn't bound to a tab slot any more (Library hosts
    /// the protocol list now) but call sites that historically
    /// switched to `.protocols` still compile, and the
    /// `pendingProtocolList` flag below routes them into the
    /// Library tab cleanly.
    case protocols
    /// Biology hub — biological-age estimate, HRV/RHR/Sleep
    /// baselines, lab markers, body composition. Replaces the
    /// prior `.insights` slot in the tab bar with a Bevel-style
    /// premium surface. The analytical / correlation content
    /// (compliance trends, HealthKit correlation, labs) still
    /// lives on `InsightsView`; future commits fold its surfaces
    /// into Biology's sections.
    case biology
    /// Profile + settings. Demoted from the bottom tab bar to a
    /// top-right avatar entry on the Today header during the
    /// training pivot, but the case stays so deep-link / state-
    /// restoration code paths keep compiling.
    case profile
}

@MainActor @Observable
final class AppState {
    var selectedTab: AppTab = .today
    /// When set, the Protocols tab pushes the matching protocol's detail view
    /// onto its navigation stack and then clears this value. Used by the
    /// profile customization sheet to deep-link from a stack row to that
    /// protocol's full detail screen.
    var pendingProtocolDeepLink: UUID?
    /// When set, the Meals tab opens the food library with the matching
    /// food pre-selected on the review screen. Only the Meals-tab
    /// instance of `HomeMealsSection` (the one with
    /// `consumesDeepLink: true`) clears it — the Today-scroll
    /// instance ignores the flag to avoid a same-runloop race
    /// between the two live mounts. Populated by the CoreSpotlight
    /// `NSUserActivity` handler so tapping a food result on the Home
    /// Screen's Spotlight pull-down lands the user directly on the
    /// log-this-food sheet, not just on the app's launch view.
    var pendingFoodLogID: FoodLogDeepLink?
    /// When true, the Biology tab opens the Labs view automatically
    /// on next appear and clears the flag. Used by Home's "latest lab"
    /// insight tap so the user lands one tap away from the trend
    /// chart inside the Biology surface.
    var pendingLabsOpen: Bool = false
    /// When set, the Home tab presents the matching `ProtocolEntry`'s
    /// dose-logging sheet automatically on next appear. Cleared the
    /// moment HomeView consumes it. Populated by the `peptidex://dose/<uuid>`
    /// deep-link handler so a tap on the Live Activity lands on the
    /// logging sheet in one bounce instead of dumping the user on the
    /// Home tab root and asking them to find the row.
    var pendingDoseLogEntryId: UUID?
    /// Set by the Sunday `peptidex://weekly/current` deep-link
    /// handler in `PeptideApp.onOpenURL`. HomeView consumes it on
    /// its next appear by pushing the matching detail view. Two-step
    /// (flag → consume) instead of pushing directly so the
    /// onOpenURL closure doesn't need a reference to HomeView's
    /// navigation path.
    var pendingWeeklyRecap: Bool = false
    /// When true, the Library tab pushes `ProtocolListView` onto its
    /// navigation stack on next appear and clears the flag.
    /// Populated by call sites that historically switched directly to
    /// the (now demoted) `.protocols` tab — Home cards, Biology
    /// shortcuts, and the profile-stacks tap — so the user lands on
    /// the protocol list in one navigation hop instead of being
    /// dumped on the peptide reference root.
    var pendingProtocolList: Bool = false
}

/// Discriminated identifier for the Spotlight deep-link payload.
/// Mirrors the namespacing in `FoodSpotlightService` — OFF favorites
/// carry a barcode, custom foods carry a UUID, recipes carry a
/// recipe UUID. The receiving view pattern-matches on the case to
/// resolve which path to take.
enum FoodLogDeepLink: Equatable, Hashable, Sendable {
    case openFoodFacts(barcode: String)
    case custom(id: UUID)
    case recipe(id: UUID)

    /// Parse a `peptidex-food/...` identifier emitted by the
    /// matching `FoodSpotlightService.identifier(...)` builder.
    /// Returns nil for any string that doesn't match a known
    /// scheme — caller falls through and the app opens to its
    /// default view.
    init?(spotlightIdentifier: String) {
        let parts = spotlightIdentifier.split(separator: "/")
        guard parts.count == 3,
              parts[0] == "peptidex-food"
        else { return nil }
        let payload = String(parts[2])
        switch parts[1] {
        case "custom":
            guard let uuid = UUID(uuidString: payload) else { return nil }
            self = .custom(id: uuid)
        case "off":
            // OFF barcodes are 8-14 ASCII digits. A malicious
            // NSUserActivity (Handoff sync, a crafted Spotlight
            // donation by another app) could push arbitrary strings
            // through this path otherwise; the validated shape
            // matches `OpenFoodFactsService.normalize(barcode:)`.
            guard (8...14).contains(payload.count),
                  payload.allSatisfy({ $0.isASCII && $0.isNumber })
            else { return nil }
            self = .openFoodFacts(barcode: payload)
        case "recipe":
            guard let uuid = UUID(uuidString: payload) else { return nil }
            self = .recipe(id: uuid)
        default:
            return nil
        }
    }
}
