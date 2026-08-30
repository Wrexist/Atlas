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
    /// Triggered by the trailing "+" quick-log button. Parent decides
    /// what to surface (meal scan, dose entry, check-in).
    let onQuickLog: () -> Void

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
                    .foregroundStyle(isActive ? .white : anchor.accent)
                Text(anchor.label)
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(isActive ? .white : AppColor.textPrimary)
            }
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 36)
            .background {
                Capsule()
                    .fill(
                        isActive
                            ? AnyShapeStyle(anchor.accent)
                            : AnyShapeStyle(AppColor.surfaceSecondary.opacity(0.65))
                    )
                    .overlay {
                        Capsule().strokeBorder(
                            isActive
                                ? AppColor.onAccent.opacity(0.25)
                                : AppColor.glassBorder,
                            lineWidth: 0.5
                        )
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(anchor.label)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    private var quickLogButton: some View {
        Button {
            Haptics.impact(.medium)
            onQuickLog()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "plus")
                    .font(AppFont.scaled(13, weight: .heavy))
                Text("Log")
                    .font(AppFont.scaled(13, weight: .heavy))
            }
            .foregroundStyle(AppColor.onAccent)
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 36)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColor.ctaGradientStart,
                                AppColor.ctaGradientEnd,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Quick log")
        .accessibilityHint("Opens a menu to log a meal, a dose, or a daily check-in.")
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
                onQuickLog: {}
            )
            TodayJumpBar(
                activeAnchor: nil,
                showsDoses: false,
                onSelect: { _ in },
                onQuickLog: {}
            )
        }
        .padding(Spacing.lg)
    }
    .preferredColorScheme(.dark)
}
