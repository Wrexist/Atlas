import SwiftUI

/// Glass-material compressing top bar that fades in over the Today
/// scroll once the welcome card scrolls past its midpoint. Mirrors
/// the pattern Apple uses in Notes / Reminders / Music — a rich
/// header card lives in the scroll content, then a slim sticky
/// surface takes over so the user always sees who they are + can
/// reach their avatar without scrolling back to the top.
///
/// `progress` drives the entire animation: 0 = invisible, 1 = fully
/// shown. Caller computes the curve from scroll offset; this view
/// stays a pure function of that input so previews and unit
/// scrubbing are trivial.
struct HomeStickyHeader: View {
    /// User's first name, already trimmed by the caller. Empty
    /// string falls back to "Today" so the bar still reads cleanly
    /// for users who haven't filled in their name yet.
    let firstName: String
    /// Cached avatar image data from `UserProfile.avatarImageData`.
    /// Nil renders the system silhouette glyph in the chip.
    let avatarImageData: Data?
    let onAvatarTap: () -> Void
    /// 0…1 fade + slide progress. Caller derives this from scroll
    /// offset; the view multiplies it against every animated
    /// property so a single source of truth drives the transition.
    let progress: Double

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(displayText)
                .font(AppFont.scaled(16, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                // Slight upward slide as the bar materialises —
                // sells the "I'm taking over from the welcome card"
                // beat without a hard pop-in.
                .offset(y: (1 - progress) * 6)

            Spacer(minLength: 0)

            avatarChip
                .offset(y: (1 - progress) * 6)
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.sm)
        .background { GlassBarBackground(opacity: progress) }
        .overlay(alignment: .bottom) {
            // Hairline divider that arrives with the rest of the
            // bar. 0.5pt to read crisp on Retina without looking
            // like a border.
            Rectangle()
                .fill(AppColor.glassBorder)
                .frame(height: 0.5)
                .opacity(progress * 0.8)
        }
        .opacity(progress)
        // Once the bar is more than half shown, tap on the chip
        // should fire — below that threshold, taps pass through to
        // the scroll content so the user doesn't get blocked
        // pre-animation.
        .allowsHitTesting(progress > 0.5)
        .accessibilityElement(children: .contain)
        .accessibilityHidden(progress < 0.5)
    }

    private var displayText: String {
        let trimmed = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return String(localized: "Today") }
        return String(format: String(localized: "Hi, %@"), trimmed)
    }

    @ViewBuilder
    private var avatarChip: some View {
        Button(action: onAvatarTap) {
            ZStack {
                Circle()
                    .fill(AppColor.surfaceSecondary)
                    .overlay {
                        Circle().strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
                if let data = avatarImageData,
                   let uiImage = AvatarImageCache.shared.image(for: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.fill")
                        .font(AppFont.scaled(13, weight: .heavy))
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open profile customisation")
    }
}

#Preview("Hidden") {
    VStack {
        HomeStickyHeader(
            firstName: "Alex",
            avatarImageData: nil,
            onAvatarTap: {},
            progress: 0
        )
        Spacer()
    }
    .background(AppColor.background)
    .preferredColorScheme(.dark)
}

#Preview("Shown") {
    VStack {
        HomeStickyHeader(
            firstName: "Alex",
            avatarImageData: nil,
            onAvatarTap: {},
            progress: 1
        )
        Spacer()
    }
    .background(AppColor.background)
    .preferredColorScheme(.dark)
}
