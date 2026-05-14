import SwiftUI

/// Hosts the Home and Lifestyle sub-screens under a shared floating top
/// tab bar. Each section keeps its own `NavigationStack` so deep links
/// and `.navigationDestination` modifiers stay scoped, and the top bar
/// is overlaid as a `safeAreaInset` so the underlying ScrollViews
/// naturally clear the pill instead of hard-coding a magic top padding.
///
/// Both subviews are mounted simultaneously and gated by opacity +
/// `allowsHitTesting` so switching sections preserves each stack's
/// push history, scroll position, and any half-completed sheet state.
/// A `switch`-driven view swap would have torn the unselected hierarchy
/// down and recreated it on every pill tap — wrong for an "independent
/// stacks" model.
struct HomeContainerView: View {
    @Environment(DataStore.self) private var dataStore

    @State private var section: HomeSection = .home
    @Namespace private var tabNamespace

    var body: some View {
        ZStack(alignment: .top) {
            HomeView()
                .opacity(section == .home ? 1 : 0)
                .allowsHitTesting(section == .home)
                .accessibilityHidden(section != .home)

            LifestyleView()
                .opacity(section == .lifestyle ? 1 : 0)
                .allowsHitTesting(section == .lifestyle)
                .accessibilityHidden(section != .lifestyle)
        }
        .animation(.easeInOut(duration: 0.22), value: section)
        .safeAreaInset(edge: .top, spacing: 0) {
            HomeTopTabBar(
                selection: $section,
                namespace: tabNamespace,
                hapticsEnabled: dataStore.profile.hapticFeedbackEnabled
            )
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.xs)
            .padding(.bottom, Spacing.sm)
            .background {
                LinearGradient(
                    colors: [
                        AppColor.background,
                        AppColor.background.opacity(0.85),
                        AppColor.background.opacity(0.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }
        }
    }
}

#Preview("Container") {
    HomeContainerView()
        .environment(DataStore(seedSampleData: true))
        .environment(AppState())
        .preferredColorScheme(.dark)
}
