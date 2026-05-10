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
}
