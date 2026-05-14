import SwiftUI

/// Two top-level segments shown inside the Home tab. Lifestyle used to
/// be a separate bottom tab but was rolled into "More" on smaller phones
/// once the app exceeded five tabs. Surfacing it as a top tab keeps it
/// one tap away without exceeding iOS's bottom-tab budget.
enum HomeSection: String, CaseIterable, Identifiable {
    case home
    case lifestyle

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .lifestyle: "Lifestyle"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .lifestyle: "leaf.fill"
        }
    }
}

/// Floating Liquid Glass pill that mirrors the iOS 26 bottom tab bar
/// treatment but sits at the top of Home. The selection pill morphs
/// between segments via `matchedGeometryEffect`, the container picks
/// up the system glass material on iOS 26+, and presses fire a
/// selection-change haptic so the control feels tactile.
struct HomeTopTabBar: View {
    @Binding var selection: HomeSection
    var namespace: Namespace.ID
    var hapticsEnabled: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            ForEach(HomeSection.allCases) { section in
                segment(section)
            }
        }
        .padding(5)
        .background {
            Capsule(style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.55))
                .overlay {
                    Capsule(style: .continuous)
                        .fill(AppColor.cardOverlay)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
        .liquidGlass(.capsule)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .shadow(color: AppColor.accentPrimary.opacity(0.18), radius: 22, y: 10)
        .accessibilityElement(children: .contain)
    }

    private func segment(_ section: HomeSection) -> some View {
        let isSelected = selection == section
        return Button {
            guard selection != section else { return }
            if hapticsEnabled {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                selection = section
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(section.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
            .foregroundStyle(isSelected ? Color.white : AppColor.textSecondary)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColor.accentPrimary.opacity(0.95),
                                    AppColor.accentLight.opacity(0.95),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                        }
                        .shadow(color: AppColor.accentPrimary.opacity(0.45), radius: 10, y: 4)
                        .matchedGeometryEffect(id: "homeTopTabPill", in: namespace)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    @Previewable @Namespace var ns
    @Previewable @State var section: HomeSection = .home
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack {
            HomeTopTabBar(selection: $section, namespace: ns)
                .padding(.horizontal, Spacing.screenPadding)
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}
