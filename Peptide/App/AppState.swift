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
}
