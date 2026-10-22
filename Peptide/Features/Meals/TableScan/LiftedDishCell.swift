import SwiftUI

/// One cut-out on the "Nice table." review grid, before it is kept.
struct ReviewDish: Identifiable {
    enum Reading: Equatable {
        case pending
        case read(TableDishReader.Reading)
        case failed(String)
    }

    let id: UUID
    let sticker: UIImage
    /// Where it sat in the photo, 0…1.
    let frame: CGRect
    var include = true
    var kind: DishKind = .food
    var name = ""
    var reading: Reading = .pending

    init(_ lifted: TableLiftEngine.Lifted) {
        id = lifted.id
        sticker = lifted.sticker
        frame = lifted.frame
    }

    var isKeepable: Bool {
        guard include, case .read = reading else { return false }
        return true
    }
}

/// Grid cell: the sticker with its keep tick, the Food / Drinks / Others
/// switch, an optional name, and what the scan read.
struct LiftedDishCell: View {
    @Binding var dish: ReviewDish
    /// False while the sticker is still flying out of the photo; the slot
    /// holds its space so the grid doesn't reflow under it.
    let isLanded: Bool
    let namespace: Namespace.ID
    let onRetry: () -> Void

    static let stickerHeight: CGFloat = 120

    var body: some View {
        VStack(spacing: Spacing.sm) {
            sticker
            DishKindPicker(selection: $dish.kind)
            TextField("Name it (optional)", text: $dish.name)
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textPrimary)
                .submitLabel(.done)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: Spacing.minimumHitTarget)
                .glassControl(.capsule, interactive: false)
                .accessibilityLabel("Dish name")
            suggestion
        }
        .opacity(dish.include ? 1 : 0.45)
        .appAnimation(AppAnimation.springSnappy, value: dish.include)
        .appAnimation(AppAnimation.step, value: dish.reading)
    }

    private var sticker: some View {
        Button {
            dish.include.toggle()
            Haptics.selection()
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if isLanded {
                        Image(uiImage: dish.sticker)
                            .resizable()
                            .scaledToFit()
                            .frame(height: Self.stickerHeight)
                            .matchedGeometryEffect(id: dish.id, in: namespace)
                            .shadow(color: .black.opacity(dish.include ? 0.18 : 0.06), radius: 8, y: 4)
                            .saturation(dish.include ? 1 : 0)
                            .scaleEffect(dish.include ? 1 : 0.9)
                    } else {
                        Color.clear.frame(height: Self.stickerHeight)
                    }
                }
                .frame(maxWidth: .infinity)

                Image(systemName: dish.include ? "checkmark.circle.fill" : "circle")
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(dish.include ? AppColor.accentPrimary : AppColor.textTertiary)
                    .background(Circle().fill(AppColor.background).padding(Spacing.xxs))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: dish.include)
                    .opacity(isLanded ? 1 : 0)
                    .scaleEffect(isLanded ? 1 : 0.4)
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.96))
        .accessibilityLabel(Text(dish.name.isEmpty ? suggestedName : dish.name))
        .accessibilityValue(dish.include ? Text("Kept") : Text("Left out"))
        .accessibilityHint("Double-tap to keep or leave out this dish.")
    }

    private var suggestedName: String {
        if case .read(let reading) = dish.reading { return reading.name }
        return String(localized: "Dish")
    }

    /// The scan's answer swaps in where the placeholder was, growing in
    /// from the chip's leading edge.
    private var suggestion: some View {
        Group { suggestionContent }
            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
    }

    @ViewBuilder
    private var suggestionContent: some View {
        switch dish.reading {
        case .pending:
            Capsule()
                .fill(AppColor.textTertiary.opacity(0.2))
                .frame(width: 96, height: 20)
                .shimmer()
                .accessibilityLabel("Reading dish")
        case .read(let reading):
            Button {
                dish.name = reading.name
                Haptics.selection()
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "sparkles")
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(AppColor.accentLight)
                        .accessibilityHidden(true)
                    Text(reading.name)
                        .lineLimit(1)
                    Text("· \(reading.calories) kcal")
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textPrimary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .glassControl(.capsule, tint: AppColor.accentPrimary.opacity(0.12), interactive: false)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.95))
            .minimumHitArea()
            .accessibilityHint("Uses this name for the dish.")
        case .failed:
            Button(action: onRetry) {
                Label("Couldn't read · Retry", systemImage: "arrow.clockwise")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: Spacing.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// The small three-way Food / Drinks / Others switch under each dish.
/// Narrower than `GlassSegmentedControl`, which doesn't fit three
/// labels in half a sheet's width.
struct DishKindPicker: View {
    @Binding var selection: DishKind
    @Namespace private var pill

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(DishKind.allCases) { kind in
                Button {
                    selection = kind
                    Haptics.selection()
                } label: {
                    Text(kind.label)
                        .font(AppFont.caption2)
                        .fontWeight(selection == kind ? .semibold : .regular)
                        .foregroundStyle(selection == kind ? AppColor.textPrimary : AppColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background {
                            if selection == kind {
                                Capsule()
                                    .fill(AppColor.background)
                                    .matchedGeometryEffect(id: "kind", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == kind ? .isSelected : [])
            }
        }
        .padding(Spacing.xxs)
        .glassControl(.capsule, interactive: false)
        .appAnimation(AppAnimation.springSnappy, value: selection)
    }
}
