import SwiftUI

/// One glanceable number with its label — the app's single stat tile.
///
/// The value leads, the uppercase eyebrow names it, and an optional
/// footnote adds context ("of 2 400 kcal"). With an `icon`, `tint` colours
/// the icon chip (and its progress ring, when `progress` is set) and the
/// value stays primary ink; without one, `tint` moves onto the value so the
/// colour still carries its meaning (a falling HRV reads red).
///
/// VoiceOver hears one stop per tile. Pass `accessibilityLabel` when the
/// combined value + label + footnote doesn't read as a sentence.
struct StatTile: View {
    enum Surface {
        /// A recessed well, for tiles grouped inside a card.
        case inset
        /// A standalone glass card, for tiles that sit on the page.
        case glass
        /// No chrome — for tiles laid straight into a hero.
        case plain
    }

    enum Size {
        case regular
        /// The headline number on a detail screen or live hero.
        case large
    }

    let label: LocalizedStringKey
    let value: String
    var icon: String?
    var tint: Color = AppColor.textPrimary
    var footnote: String?
    var progress: Double?
    var size: Size = .regular
    var surface: Surface = .inset
    var accessibilityLabel: String?
    var action: (() -> Void)?

    /// Passed to the scaled fonts so a `.dynamicTypeSize(...)` clamp on a
    /// row of tiles actually caps them.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let action {
            Button(action: action) { tile }
                .buttonStyle(ScalePressStyle())
        } else {
            tile
        }
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let icon {
                iconChip(icon)
            }
            Text(value)
                .font(valueFont)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(icon == nil ? tint : AppColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(AppFont.scaled(AppFont.Scale.badge, weight: .heavy, relativeTo: .caption1, in: dynamicTypeSize))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let footnote {
                Text(footnote)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(StatTileSurface(surface: surface))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .modifier(StatTileAccessibilityLabel(label: accessibilityLabel))
    }

    private var valueFont: Font {
        switch size {
        case .regular: AppFont.scaled(20, weight: .heavy, design: .rounded, relativeTo: .title1, in: dynamicTypeSize)
        case .large: AppFont.scaled(28, weight: .bold, design: .rounded, relativeTo: .title1, in: dynamicTypeSize)
        }
    }

    private func iconChip(_ icon: String) -> some View {
        ZStack {
            if let progress {
                Circle()
                    .stroke(tint.opacity(0.18), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0.001, min(progress, 1)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .appAnimation(AppAnimation.springSmooth, value: progress)
            } else {
                Circle()
                    .fill(tint.opacity(0.18))
            }
            Image(systemName: icon)
                .font(AppFont.scaled(11, weight: .heavy, in: dynamicTypeSize))
                .foregroundStyle(tint)
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

private struct StatTileSurface: ViewModifier {
    let surface: StatTile.Surface

    func body(content: Content) -> some View {
        switch surface {
        case .inset:
            content
                .padding(Spacing.md)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .fill(AppColor.cardOverlay)
                        .overlay {
                            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                        }
                }
        case .glass:
            content
                .padding(Spacing.md)
                .glassSurface(cornerRadius: Spacing.smallCornerRadius)
        case .plain:
            content
        }
    }
}

private struct StatTileAccessibilityLabel: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label {
            content.accessibilityLabel(label)
        } else {
            content
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: Spacing.lg) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                StatTile(label: "Calories", value: "1280", icon: "flame.fill",
                         tint: AppColor.macroProtein, footnote: "of 2400 kcal", progress: 0.53)
                StatTile(label: "Water", value: "48", icon: "drop.fill",
                         tint: AppColor.macroWater, footnote: "oz today")
                StatTile(label: "Compliance", value: "86%", tint: AppColor.accentPrimary,
                         footnote: "12 of 14 doses", size: .large)
                StatTile(label: "HRV Δ", value: "-4 ms", tint: AppColor.negative)
            }
            HStack(spacing: Spacing.sm) {
                StatTile(label: "Streak", value: "12", icon: "flame.fill",
                         tint: AppColor.warning, surface: .glass)
                StatTile(label: "Days", value: "140", icon: "calendar",
                         tint: AppColor.accentPrimary, surface: .glass, action: {})
            }
        }
        .padding(Spacing.screenPadding)
    }
    .background(AppColor.background)
}
