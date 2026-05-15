import SwiftUI

enum AppTab: String, CaseIterable {
    case home
    case database
    case protocols
    case analytics
    case profile
}

@MainActor @Observable
final class AppState {
    var selectedTab: AppTab = .home
    /// When set, the Protocols tab pushes the matching protocol's detail view
    /// onto its navigation stack and then clears this value. Used by the
    /// profile customization sheet to deep-link from a stack row to that
    /// protocol's full detail screen.
    var pendingProtocolDeepLink: UUID?
    /// When set, the Lifestyle tab opens the food library with the
    /// matching food pre-selected on the review screen. Cleared the
    /// moment Lifestyle consumes it. Populated by the CoreSpotlight
    /// `NSUserActivity` handler so tapping a food result on the Home
    /// Screen's Spotlight pull-down lands the user directly on the
    /// log-this-food sheet, not just on the app's launch view.
    var pendingFoodLogID: FoodLogDeepLink?
}

/// Discriminated identifier for the Spotlight deep-link payload.
/// Mirrors the namespacing in `FoodSpotlightService` — OFF favorites
/// carry a barcode, custom foods carry a UUID, recipes carry a
/// recipe UUID. The receiving view pattern-matches on the case to
/// resolve which path to take.
enum FoodLogDeepLink: Equatable, Sendable {
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
            guard !payload.isEmpty else { return nil }
            self = .openFoodFacts(barcode: payload)
        case "recipe":
            guard let uuid = UUID(uuidString: payload) else { return nil }
            self = .recipe(id: uuid)
        default:
            return nil
        }
    }
}
