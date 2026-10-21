import SwiftUI

/// The small capsule flag that sits beside a title — PRO, DEMO, Get started.
/// One shape and one type size (`AppFont.badge`) so every flag in the app
/// reads as the same element.
///
/// - `.tinted`: a translucent wash of `tint` with the accent ink, for a
///   quiet label.
/// - `.solid`: a filled capsule with `AppColor.onAccent` ink, for a flag
///   that has to stand out from its row.
struct Badge: View {
    enum Style {
        case tinted
        case solid
    }

    private let text: LocalizedStringKey
    private let icon: String?
    private let style: Style
    private let tint: Color?

    /// - Parameter tint: overrides the accent (wash and ink when tinted, fill
    ///   when solid); leave `nil` for the theme's accent — `accentFill` when
    ///   solid, so `onAccent` ink keeps its contrast.
    init(
        _ text: LocalizedStringKey,
        icon: String? = nil,
        style: Style = .tinted,
        tint: Color? = nil
    ) {
        self.text = text
        self.icon = icon
        self.style = style
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            if let icon {
                Image(systemName: icon)
                    .accessibilityHidden(true)
            }
            Text(text)
                .tracking(0.5)
        }
        .font(AppFont.badge)
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(ink)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs)
        .background { capsule }
    }

    private var ink: Color {
        switch style {
        case .tinted: tint ?? AppColor.accentInkOnWash
        case .solid: AppColor.onAccent
        }
    }

    @ViewBuilder
    private var capsule: some View {
        switch style {
        case .tinted:
            Capsule()
                .fill((tint ?? AppColor.accentPrimary).opacity(0.2))
                .overlay {
                    Capsule().strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                }
        case .solid:
            Capsule().fill(tint ?? AppColor.accentFill)
        }
    }
}

/// The Pro entitlement flag.
struct ProBadge: View {
    var body: some View {
        Badge("PRO", icon: "star.fill")
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.sm) {
            ProBadge()
            Badge("PRO", style: .solid)
            Badge("DEMO", style: .solid, tint: AppColor.recap)
            Badge("Get started", style: .solid)
        }
    }
}
