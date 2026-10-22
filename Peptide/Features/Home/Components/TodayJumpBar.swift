import SwiftUI

/// Horizontal pill bar of "jump to section" shortcuts that sits at the
/// top of Today so the user doesn't have to scroll past five cards to
/// reach Meals / Wellness / Movement. Each chip is a `SectionAnchor`
/// case; `onSelect` is the parent's hook to scroll to that anchor (or
/// switch tabs, in the case of Insights).
///
/// `activeAnchor` lights the chip closest to the top of the viewport,
/// giving the user a "you are here" indicator while they scroll —
/// same pattern Apple Health / Fitness use for their stacked daily
/// pages.
struct TodayJumpBar: View {
    /// Section anchor identifiers used by the parent's
    /// `ScrollViewReader` to scroll to a tagged section. The former
    /// `meals` and `biology` chips switched tabs — a duplicate of the
    /// tab bar one centimetre below them — and were dropped in the
    /// Product Architecture 07 pass; every remaining chip scrolls
    /// within Today.
    enum SectionAnchor: Hashable, CaseIterable {
        case doses, wellness, movement

        var label: LocalizedStringKey {
            switch self {
            case .doses:    "Doses"
            case .wellness: "Wellness"
            case .movement: "Movement"
            }
        }

        var systemImage: String {
            switch self {
            case .doses:    "syringe.fill"
            case .wellness: "heart.text.square.fill"
            case .movement: "figure.run"
            }
        }

        var accent: Color {
            switch self {
            case .doses:    AppColor.accentPrimary
            case .wellness: AppColor.metricHRV
            case .movement: AppColor.metricActivity
            }
        }
    }

    let activeAnchor: SectionAnchor?
    /// Whether the user has any logged protocols. When false we drop
    /// the Doses chip — there's nothing for it to scroll to.
    let showsDoses: Bool
    let onSelect: (SectionAnchor) -> Void
    /// Whether the parent's quick-log sheet is up. Turns the "+" into a
    /// "×" so the control reads as the thing that opened the sheet.
    let isQuickLogOpen: Bool
    /// Whether "+ Log" opens the meal-or-dose menu. Without a pending
    /// dose it goes straight to the meal scanner, and the hint says so.
    let quickLogIncludesDose: Bool
    /// Triggered by the trailing "+" quick-log button. Parent decides
    /// what to surface (meal scan, dose entry).
    let onQuickLog: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var activePill

    private var chips: [SectionAnchor] {
        SectionAnchor.allCases.filter { $0 != .doses || showsDoses }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(chips, id: \.self) { anchor in
                    chipButton(for: anchor)
                }
                quickLogButton
            }
            // One pill slides between chips as the active section changes.
            .appAnimation(AppAnimation.springSnappy, value: activeAnchor)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Jump to section")
    }

    private func chipButton(for anchor: SectionAnchor) -> some View {
        let isActive = (anchor == activeAnchor)
        return Button {
            Haptics.selection()
            onSelect(anchor)
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: anchor.systemImage)
                    .font(AppFont.scaled(11, weight: .bold))
                    .foregroundStyle(isActive ? AppColor.onAccent : anchor.accent)
                Text(anchor.label)
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(isActive ? AppColor.onAccent : AppColor.textPrimary)
            }
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 36)
            .background {
                ZStack {
                    Capsule()
                        .fill(AppColor.surfaceSecondary.opacity(0.65))
                        .overlay { Capsule().strokeBorder(AppColor.glassBorder, lineWidth: 0.5) }
                    if isActive {
                        Capsule()
                            .fill(anchor.accent)
                            .overlay { Capsule().strokeBorder(AppColor.onAccent.opacity(0.25), lineWidth: 0.5) }
                            .matchedGeometryEffect(id: "activePill", in: activePill)
                    }
                }
            }
            .minimumHitArea()
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel(anchor.label)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    private var quickLogButton: some View {
        Button {
            Haptics.impact(.medium)
            onQuickLog()
        } label: {
            HStack(spacing: Spacing.xs) {
                // Rotating "+" 45° draws the "×"; under Reduce Motion the
                // glyph swaps instead so nothing spins.
                Image(systemName: isQuickLogOpen && reduceMotion ? "xmark" : "plus")
                    .font(AppFont.scaled(13, weight: .heavy))
                    .rotationEffect(.degrees(isQuickLogOpen && !reduceMotion ? 45 : 0))
                    .animation(
                        AppAnimation.motionAware(AppAnimation.springSnappy, reduceMotion: reduceMotion),
                        value: isQuickLogOpen
                    )
                Text("Log")
                    .font(AppFont.scaled(13, weight: .heavy))
            }
            .foregroundStyle(AppColor.onAccent)
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 36)
            // The user's theme accent, not the fixed purple CTA
            // gradient that clashed with every other theme.
            .background { Capsule().fill(AppColor.accentFill) }
            .minimumHitArea()
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel("Quick log")
        .accessibilityHint(quickLogIncludesDose
            ? Text("Opens a menu to snap a meal photo or log your next dose.")
            : Text("Opens the meal scanner."))
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.lg) {
            TodayJumpBar(
                activeAnchor: .wellness,
                showsDoses: true,
                onSelect: { _ in },
                isQuickLogOpen: false,
                quickLogIncludesDose: true,
                onQuickLog: {}
            )
            TodayJumpBar(
                activeAnchor: nil,
                showsDoses: false,
                onSelect: { _ in },
                isQuickLogOpen: true,
                quickLogIncludesDose: false,
                onQuickLog: {}
            )
        }
        .padding(Spacing.lg)
    }
    .preferredColorScheme(.dark)
}
