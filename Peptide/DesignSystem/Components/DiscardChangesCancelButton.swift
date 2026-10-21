import SwiftUI

/// An editor sheet's Cancel button that asks before throwing away edits.
/// Pair it with `.interactiveDismissDisabled(hasChanges)` so a stray
/// swipe can't skip the question.
struct DiscardChangesCancelButton: View {
    let hasChanges: Bool
    let onCancel: () -> Void

    @State private var isConfirming = false

    var body: some View {
        Button("Cancel") {
            if hasChanges { isConfirming = true } else { onCancel() }
        }
        .confirmationDialog("Discard changes?", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive, action: onCancel)
            Button("Keep editing", role: .cancel) {}
        }
    }
}
