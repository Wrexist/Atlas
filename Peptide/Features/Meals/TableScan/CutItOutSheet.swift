import SwiftUI

/// "Cut it out myself": a circle the user drags and pinches over the dish
/// the automatic cut missed. Plates are round, so a circle is the cut
/// that is right far more often than a lasso would be worth.
struct CutItOutSheet: View {
    let photo: UIImage
    let onCut: (CGRect) -> Void

    @Environment(\.dismiss) private var dismiss
    /// Centre and radius, normalised to the photo's short edge.
    @State private var center = CGPoint(x: 0.5, y: 0.5)
    @State private var radius: CGFloat = 0.22
    @State private var dragStart: CGPoint?
    @State private var pinchStart: CGFloat?

    private static let radiusRange: ClosedRange<CGFloat> = 0.06...0.5

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                Text("Drag the circle over the dish, pinch to fit it.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                GeometryReader { geo in
                    let fit = fitRect(in: geo.size)
                    let short = min(fit.width, fit.height)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(width: fit.width, height: fit.height)
                            .offset(x: fit.minX, y: fit.minY)

                        Circle()
                            .strokeBorder(AppColor.onAccent, lineWidth: 3)
                            .background(Circle().fill(AppColor.accentPrimary.opacity(0.15)))
                            .frame(width: radius * short * 2, height: radius * short * 2)
                            .position(
                                x: fit.minX + center.x * fit.width,
                                y: fit.minY + center.y * fit.height
                            )
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                    .gesture(drag(in: fit).simultaneously(with: pinch))
                }
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))

                GlassButton(title: "Cut it out", icon: "scissors", style: .primary, isFullWidth: true) {
                    onCut(normalisedCircle)
                    Haptics.impact(.medium)
                    dismiss()
                }
            }
            .padding(Spacing.xl)
            .background(AppColor.background)
            .navigationTitle("Cut it out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }

    private func fitRect(in size: CGSize) -> CGRect {
        let photoSize = photo.size
        guard photoSize.width > 0, photoSize.height > 0 else { return CGRect(origin: .zero, size: size) }
        let scale = min(size.width / photoSize.width, size.height / photoSize.height)
        let fitted = CGSize(width: photoSize.width * scale, height: photoSize.height * scale)
        return CGRect(
            x: (size.width - fitted.width) / 2,
            y: (size.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    /// The circle's bounding square as a 0…1 frame of the photo.
    private var normalisedCircle: CGRect {
        let short = min(photo.size.width, photo.size.height)
        let width = radius * 2 * short / max(photo.size.width, 1)
        let height = radius * 2 * short / max(photo.size.height, 1)
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private func drag(in fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStart ?? center
                dragStart = start
                center = CGPoint(
                    x: min(max(start.x + value.translation.width / max(fit.width, 1), 0), 1),
                    y: min(max(start.y + value.translation.height / max(fit.height, 1), 0), 1)
                )
            }
            .onEnded { _ in dragStart = nil }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? radius
                pinchStart = start
                radius = min(max(start * value.magnification, Self.radiusRange.lowerBound), Self.radiusRange.upperBound)
            }
            .onEnded { _ in pinchStart = nil }
    }
}
