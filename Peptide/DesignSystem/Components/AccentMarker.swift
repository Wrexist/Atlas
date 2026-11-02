import SwiftUI

/// The small rounded accent square that leads a section's label. It
/// carries the brand colour so the label beside it can stay a calm grey:
/// one quiet dot of colour reads as premium where a coloured, tracked,
/// uppercase eyebrow shouts.
struct AccentMarker: View {
    var size: CGFloat = 10

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(AppColor.accentPrimary)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
