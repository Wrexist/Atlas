import SpriteKit
import SwiftUI

/// The top of the fridge: what is in, as floating cut-outs on the dotted
/// table cloth the table scan uses. At rest they bob gently, a little
/// turned; Float hands them to the table's physics in drift mode, where
/// they wander and can be flicked. Tapping one opens it.
struct FridgeShelf: View {
    let entries: [Entry]
    /// Owned by the host so the Float toggle can sit in the row under the
    /// shelf instead of on top of the groceries.
    @Binding var isFloating: Bool
    let open: (UUID) -> Void

    struct Entry: Identifiable {
        let id: UUID
        let product: FridgeProduct
        let count: Int
        let needsUse: Bool
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var store = FridgeStore.shared
    @State private var scene = PlateTableScene(size: CGSize(width: 1, height: 1))
    @State private var isBobbing = false
    @State private var size: CGSize = .zero

    /// The shelf stays readable up to here; the list below has the rest.
    static let maxShown = 9

    private var shown: [Entry] { Array(entries.prefix(Self.maxShown)) }

    var body: some View {
        ZStack {
            FridgeShelfSurface()
            if isFloating {
                SpriteView(scene: scene, options: [.allowsTransparency])
                    .accessibilityLabel("Your groceries, floating. Tilt your phone or flick them.")
            } else {
                resting
            }
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .onChange(of: isFloating) { _, floating in if floating { startPhysics() } }
        .onChange(of: shown.map(\.id)) { _, _ in if isFloating { startPhysics() } }
        .onChange(of: canFloat) { _, allowed in if !allowed { isFloating = false } }
    }

    private var resting: some View {
        let cells = PlateTableLayout.cells(count: shown.count, in: size, spacing: Spacing.md)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(zip(shown, cells).enumerated()), id: \.element.0.id) { index, pair in
                let (entry, cell) = pair
                Button { open(entry.id) } label: {
                    sticker(entry, side: cell.width * 0.86)
                        .rotationEffect(.degrees(Self.tilt(index)))
                        .offset(y: isBobbing ? (index.isMultiple(of: 2) ? -4 : 4) : 0)
                }
                .buttonStyle(ScalePressStyle(pressedScale: 0.92))
                .staggeredAppear(index: index)
                .position(x: cell.midX, y: cell.midY)
                .accessibilityLabel(Text(entry.product.displayName))
                .accessibilityHint("Opens this item.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .motionAwareLoop(AppAnimation.breathe, autoreverses: true, isRunning: $isBobbing)
    }

    private func sticker(_ entry: Entry, side: CGFloat) -> some View {
        FridgeProductImage(product: entry.product, size: side)
            .appShadow(AppShadow.glassElevated)
            .overlay(alignment: .topTrailing) {
                if entry.count > 1 {
                    Text("\(entry.count)")
                        .font(AppFont.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.onAccent)
                        .padding(.horizontal, Spacing.xs)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(AppColor.accentFill, in: Capsule())
                }
            }
            .overlay(alignment: .bottom) {
                if entry.needsUse {
                    Image(systemName: "clock.badge.exclamationmark.fill")
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(AppColor.warning)
                        .padding(Spacing.xxs)
                        .background(AppColor.background, in: Circle())
                        .offset(y: Spacing.xs)
                        .accessibilityLabel("Use soon")
                }
            }
    }

    /// Fixed per position so the shelf looks the same every visit.
    private static func tilt(_ index: Int) -> Double {
        [-6, 4, -3, 5, -5, 3, -4, 6, -2][index % 9]
    }

    /// Drifting physics is motion Reduce Motion asks to avoid, and items
    /// in play can't be opened one by one with VoiceOver.
    private var canFloat: Bool { FridgeFloatToggle.isAllowed(reduceMotion: reduceMotion, voiceOver: voiceOverEnabled) && !shown.isEmpty }

    private func startPhysics() {
        let cells = PlateTableLayout.cells(count: shown.count, in: size, spacing: Spacing.md)
        let plates = zip(shown, cells).compactMap { entry, cell -> PlateTableScene.Plate? in
            guard let image = store.photo(for: entry.product) ?? placeholder(entry, side: cell.width) else { return nil }
            let frame = PlateTableLayout.fit(image.size, in: cell.insetBy(dx: cell.width * 0.07, dy: cell.height * 0.07))
            return .init(id: entry.id, image: image, label: entry.product.name, frame: frame)
        }
        scene.size = size
        scene.onTap = { open($0) }
        scene.place(plates, labelColor: UIColor(AppColor.textPrimary))
        scene.setLabelsVisible(false)
        scene.setMode(.drift)
    }

    /// The packshot or artwork drawn once, for a product with no cut-out.
    private func placeholder(_ entry: Entry, side: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: FridgeProductImage(product: entry.product, size: side))
        renderer.scale = 2
        return renderer.uiImage
    }
}

/// The dotted cloth under the shelf, fading into the screen at the bottom.
private struct FridgeShelfSurface: View {
    var body: some View {
        AppColor.surfaceSecondary
            .overlay {
                Canvas { context, size in
                    let step: CGFloat = 18
                    var dots = Path()
                    for x in stride(from: step / 2, to: size.width, by: step) {
                        for y in stride(from: step / 2, to: size.height, by: step) {
                            dots.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                        }
                    }
                    context.fill(dots, with: .color(AppColor.textTertiary.opacity(0.18)))
                }
            }
            .accessibilityHidden(true)
    }
}

/// Float / Settle for the shelf. Hidden when floating isn't allowed:
/// drifting physics is motion Reduce Motion asks to avoid, and items in
/// play can't be opened one by one with VoiceOver.
struct FridgeFloatToggle: View {
    @Binding var isFloating: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    static func isAllowed(reduceMotion: Bool, voiceOver: Bool) -> Bool { !reduceMotion && !voiceOver }

    var body: some View {
        if Self.isAllowed(reduceMotion: reduceMotion, voiceOver: voiceOverEnabled) {
            Button {
                Haptics.selection()
                AppAnimation.with(AppAnimation.fadeIn) { isFloating.toggle() }
            } label: {
                Label(isFloating ? "Settle" : "Float", systemImage: isFloating ? "square.grid.3x3.fill" : "wind")
                    .contentTransition(.symbolEffect(.replace))
                    .font(AppFont.footnote.weight(.semibold))
                    .foregroundStyle(isFloating ? AppColor.onAccent : AppColor.textPrimary)
                    .padding(.horizontal, Spacing.md)
                    .frame(minHeight: 36)
                    .background { if isFloating { Capsule().fill(AppColor.accentFill) } }
                    .glassControl(.capsule)
            }
            .buttonStyle(ScalePressStyle())
            .minimumHitArea()
            .accessibilityAddTraits(isFloating ? .isSelected : [])
        }
    }
}
