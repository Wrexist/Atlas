import SwiftUI

/// Reports a section's frame inside Today's scroll view so
/// `HomeView` can light up the corresponding TodayJumpBar chip
/// when that section is closest to the top of the viewport.
///
/// Pattern: each anchored section calls `.trackSectionAnchor(.meals)`
/// (etc.), which paints a transparent GeometryReader behind it and
/// publishes the section's frame via this PreferenceKey. HomeView
/// reads the merged dictionary in `.onPreferenceChange` and picks
/// the nearest-to-top anchor.
///
/// Lives in its own file so neither HomeView nor the section
/// components grow another inline private type.
struct SectionAnchorFrameKey: PreferenceKey {
    static let defaultValue: [TodayJumpBar.SectionAnchor: CGRect] = [:]

    static func reduce(
        value: inout [TodayJumpBar.SectionAnchor: CGRect],
        nextValue: () -> [TodayJumpBar.SectionAnchor: CGRect]
    ) {
        // Each section emits exactly one entry; merging with "later
        // wins" gives the most recent layout pass's frame.
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    /// Stamps the receiving view's frame into
    /// `SectionAnchorFrameKey`. The host scroll view must declare
    /// `.coordinateSpace(name: "HomeScroll")` so the frames share
    /// a comparable origin across all anchored sections.
    func trackSectionAnchor(_ anchor: TodayJumpBar.SectionAnchor) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SectionAnchorFrameKey.self,
                    value: [anchor: proxy.frame(in: .named("HomeScroll"))]
                )
            }
        }
    }
}

/// Picks the anchor whose top edge is closest to (but not too far
/// past) the configured `headerInset` from the viewport top. This
/// matches how iOS apps like Health and Fitness light their
/// active section: as the user scrolls, the chip flips when the
/// next section's header has cleared the header inset.
///
/// Caller passes the dictionary from `SectionAnchorFrameKey` and
/// gets back the nearest anchor or nil when nothing is in range.
/// Pure function so the picking logic can be unit-tested without
/// SwiftUI.
enum ActiveSectionPicker {
    /// Headroom (in points) below the scroll-view top that an
    /// anchor must clear before it counts as "active". The jump
    /// bar itself sits around the top of the scroll content, so
    /// the inset keeps the bar from highlighting itself.
    static let headerInset: CGFloat = 120

    static func pick(
        from frames: [TodayJumpBar.SectionAnchor: CGRect],
        headerInset: CGFloat = headerInset
    ) -> TodayJumpBar.SectionAnchor? {
        // Sections whose top edge sits at or above `headerInset` —
        // i.e. they've scrolled into the upper portion of the
        // viewport. Among those, the one with the *largest* minY
        // is the one most recently scrolled past the inset, which
        // is what the user is reading.
        let candidates = frames.filter { _, frame in
            frame.minY <= headerInset
        }
        return candidates.max(by: { $0.value.minY < $1.value.minY })?.key
    }
}
