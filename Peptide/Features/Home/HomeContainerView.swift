import SwiftUI

/// Hosts the Home and Lifestyle sub-screens under a shared floating top
/// tab bar. Each section keeps its own `NavigationStack` so deep links
/// and `.navigationDestination` modifiers stay scoped, and the top bar
/// is overlaid as a `safeAreaInset` so the underlying ScrollViews
/// naturally clear the pill instead of hard-coding a magic top padding.
struct HomeContainerView: View {
    @Environment(DataStore.self) private var dataStore

    @State private var section: HomeSection = .home
    @Namespace private var tabNamespace

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch section {
                case .home:
                    HomeView()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .leading)),
                            removal: .opacity.combined(with: .move(edge: .trailing))
                        ))
                case .lifestyle:
                    LifestyleView()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                }
            }
        }
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
