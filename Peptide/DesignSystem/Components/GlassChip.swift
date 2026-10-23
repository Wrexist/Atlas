import SwiftUI

enum GlassChipStyle {
    /// Selected chips take a tinted glass wash and tinted ink — filter rows
    /// where the tint carries meaning (a peptide category's colour). A
    /// custom tint must be an ink stop that holds 4.5:1 on its own 0.18
    /// wash; the theme accent uses `AppColor.accentInkOnWash` for that.
    case glass
    /// Selected chips fill solid with the tint and print `AppColor.background`
    /// on top, so `tint` must be an ink-weight colour (`accentPrimary`,
    /// `textPrimary`). For dense rows where the active filter has to read
    /// from across the screen.
    case prominent
}

/// The app's one selectable chip: filter rows, category pickers, tag rows.
/// A single capsule recipe, press response, haptic, and VoiceOver
/// "selected" trait, so every chip row behaves the same.
struct GlassChip: View {
    private let title: LocalizedStringKey
    private let glyph: AppGlyph?
    /// `nil` means the theme accent.
    private let tint: Color?
    private let style: GlassChipStyle
    private let isSelected: Bool
    private let action: () -> Void

    init(
        _ title: LocalizedStringKey,
        icon: String? = nil,
        tint: Color? = nil,
        style: GlassChipStyle = .glass,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.glyph = icon.map(AppGlyph.system)
        self.tint = tint
        self.style = style
        self.isSelected = isSelected
        self.action = action
    }

    /// For an icon that may be one of the app's own asset glyphs.
    init(
        _ title: LocalizedStringKey,
        glyph: AppGlyph,
        tint: Color? = nil,
        style: GlassChipStyle = .glass,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.glyph = glyph
        self.tint = tint
        self.style = style
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button {
            if !isSelected { Haptics.selection() }
            action()
        } label: {
            HStack(spacing: Spacing.xs) {
                if let glyph {
                    GlyphImage(glyph: glyph)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(AppFont.chipText)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs + Spacing.xxs)
            .background {
                if isFilled {
                    Capsule(style: .continuous).fill(hue)
                }
            }
            .glassControl(.capsule, tint: wash, border: border, interactive: false)
            .minimumHitArea()
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var isFilled: Bool { isSelected && style == .prominent }

    private var hue: Color { tint ?? AppColor.accentPrimary }

    private var ink: Color {
        guard isSelected else { return AppColor.textSecondary }
        return style == .prominent ? AppColor.background : tint ?? AppColor.accentInkOnWash
    }

    private var wash: Color? {
        isSelected && style == .glass ? hue.opacity(0.18) : nil
    }

    private var border: Color {
        guard isSelected else { return AppColor.glassBorder }
        return style == .prominent ? .clear : hue.opacity(0.4)
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.xs) {
                GlassChip("All", isSelected: true) {}
                GlassChip("Growth", icon: "arrow.up.right", isSelected: false) {}
            }
            HStack(spacing: Spacing.xs) {
                GlassChip("All", style: .prominent, isSelected: true) {}
                GlassChip("Chest", icon: "figure.strengthtraining.traditional",
                          style: .prominent, isSelected: false) {}
            }
        }
    }
}
