import SwiftUI

/// Shimmering stand-in for a line of text or a figure that is still
/// loading. Size it to what replaces it so loading → ready doesn't shift
/// the layout. Hidden from VoiceOver: the container says it's loading,
/// not each bar.
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat = 12
    var cornerRadius: CGFloat = Spacing.xs

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AppColor.surfaceSecondary.opacity(0.7))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .shimmer()
            .accessibilityHidden(true)
    }
}
