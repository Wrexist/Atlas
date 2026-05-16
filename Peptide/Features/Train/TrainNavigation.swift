import Foundation

/// Navigation values pushed onto the Train tab's `NavigationStack`.
/// Centralised so the same enum drives `NavigationLink(value:)` calls
/// from anywhere in the tab without each call site re-declaring its
/// own destination type.
enum TrainNavigation: Hashable {
    /// Drill into the full exercise detail (instructions, muscles,
    /// images, history).
    case exerciseDetail(String)
}
