import SwiftUI

/// Today's inline navigation title. It fades in once the greeting scrolls
/// away, the way Notes and Reminders hand a large in-content title over to
/// the bar, so the user still sees whose day this is. The profile button
/// sits beside it in the bar, in the same place as on every other tab.
///
/// `progress` drives the whole effect: 0 = invisible, 1 = fully shown.
/// A binding so only this view, not the caller's body, reads it on every
/// scroll frame.
struct HomeStickyHeader: View {
    /// User's first name, already trimmed by the caller. Empty falls back
    /// to "Today" so the bar still reads cleanly without a name.
    let firstName: String
    @Binding var progress: Double

    var body: some View {
        Text(displayText)
            .font(AppFont.headline)
            .foregroundStyle(AppColor.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            // A slight upward slide sells the hand-over from the greeting
            // without a hard pop-in.
            .offset(y: (1 - progress) * 6)
            .opacity(progress)
            .accessibilityHidden(progress < 0.5)
            .accessibilityAddTraits(.isHeader)
    }

    private var displayText: String {
        let trimmed = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return String(localized: "Today") }
        return String(format: String(localized: "Hi, %@"), trimmed)
    }
}

#Preview("Shown") {
    HomeStickyHeader(firstName: "Alex", progress: .constant(1))
        .padding(Spacing.lg)
        .background(AppColor.background)
}
