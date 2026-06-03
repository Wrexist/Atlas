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
    /// `ScrollViewReader` to scroll to a tagged section. `biology`
    /// is special-cased — it jumps to the Biology tab rather than
    /// scrolling within Today.
    enum SectionAnchor: Hashable, CaseIterable {
        case doses, meals, wellness, movement, biology

        var label: LocalizedStringKey {
            switch self {
            case .doses:    "Doses"
            case .meals:    "Meals"
            case .wellness: "Wellness"
            case .movement: "Movement"
            case .biology:  "Biology"
            }
        }

        var systemImage: String {
            switch self {
            case .doses:    "syringe.fill"
            case .meals:    "fork.knife"
            case .wellness: "heart.text.square.fill"
            case .movement: "figure.run"
            case .biology:  "heart.fill"
            }
        }

        var accent: Color {
            switch self {
            case .doses:    AppColor.accentPrimary
            case .meals:    AppColor.macroProtein
            case .wellness: AppColor.metricHRV
            case .movement: AppColor.metricActivity
            case .biology:  AppColor.accentLight
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
    var hapticsEnabled: Bool = true

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
            if hapticsEnabled {
                Haptics.selection()
            }
            onSelect(anchor)
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: anchor.systemImage)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isActive ? .white : anchor.accent)
                Text(anchor.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isActive ? .white : AppColor.textPrimary)
            }
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 36)
            .background {
                Capsule()
                    .fill(
                        isActive
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [anchor.accent, anchor.accent.opacity(0.75)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(AppColor.surfaceSecondary.opacity(0.65))
                    )
                    .overlay {
                        Capsule().strokeBorder(
                            isActive
                                ? Color.white.opacity(0.25)
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
            if hapticsEnabled {
                Haptics.impact(.medium)
            }
            onQuickLog()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .heavy))
                Text("Log")
                    .font(.system(size: 13, weight: .heavy))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 36)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.310, green: 0.275, blue: 0.898),
                                Color(red: 0.486, green: 0.227, blue: 0.929),
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
                activeAnchor: .meals,
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
