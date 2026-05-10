import SwiftUI

struct ProtocolListView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState
    @State private var showingBuilder = false
    @State private var showingPaywall = false
    @State private var preselectedPeptide: Peptide?
    @State private var path: [PeptideProtocol] = []

    var body: some View {
        @Bindable var state = appState

        NavigationStack(path: $path) {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        if dataStore.protocols.isEmpty {
                            EmptyStateView(
                                icon: "list.clipboard",
                                title: "No Protocols Yet",
                                message: "Create your first peptide protocol to start tracking your regimen.",
                                action: .init(title: "Create Protocol", icon: "plus") {
                                    if dataStore.profile.hapticFeedbackEnabled {
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    }
                                    showingBuilder = true
                                }
                            )
                            .padding(.top, Spacing.xxl)
                            .sectionAppear(index: 0)
                        } else {
                            if !dataStore.activeProtocols.isEmpty {
                                ProtocolSection(title: "Active", protocols: dataStore.activeProtocols)
                            }

                            if !dataStore.pausedProtocols.isEmpty {
                                ProtocolSection(title: "Paused", protocols: dataStore.pausedProtocols)
                            }

                            if !dataStore.completedProtocols.isEmpty {
                                ProtocolSection(title: "Completed", protocols: dataStore.completedProtocols)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.bottom, 100)
                }
                .background(AppColor.background)

                // Floating add button
                GlassIconButton(icon: "plus", accessibilityLabel: "New protocol", size: 56, tinted: true) {
                    preselectedPeptide = nil
                    let blocked = StoreService.shared.requiresPro(
                        activeProtocolCount: dataStore.activeProtocols.count
                    )
                    if dataStore.profile.hapticFeedbackEnabled {
                        if blocked {
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        } else {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    }
                    if blocked {
                        showingPaywall = true
                    } else {
                        showingBuilder = true
                    }
                }
                .appShadow(AppShadow.accentGlow)
                .padding(Spacing.xxl)
            }
            .refreshable {
                // Re-load from disk via the repo so a CloudKit sync from
                // another device shows up without restarting the app. The
                // repo loads are fast (single JSON read per file) so this
                // can happen on every pull-to-refresh.
                dataStore.reloadFromDisk()
            }
            .navigationTitle("Protocols")
            .navigationDestination(for: PeptideProtocol.self) { protocol_ in
                ProtocolDetailView(protocol_: protocol_)
            }
            .glassSheet(isPresented: $showingBuilder) {
                ProtocolBuilderView(preselectedPeptide: preselectedPeptide)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
                    .liquidGlassPresentation()
            }
            .onAppear { consumePendingDeepLink() }
            .onChange(of: appState.pendingProtocolDeepLink) { _, _ in
                consumePendingDeepLink()
            }
        }
    }

    /// Pushes the deep-linked protocol onto the navigation path if the user
    /// has it. Cleared immediately so a re-tap of the same row navigates
    /// again (otherwise the value would be a no-op on the second tap).
    private func consumePendingDeepLink() {
        guard let id = appState.pendingProtocolDeepLink,
              let target = dataStore.protocols.first(where: { $0.id == id })
        else { return }
        if path.last?.id != target.id {
            path.append(target)
        }
        appState.pendingProtocolDeepLink = nil
    }
}

private struct ProtocolSection: View {
    let title: String
    let protocols: [PeptideProtocol]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title.uppercased())
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
                .tracking(1.5)
                .padding(.leading, Spacing.xs)

            ForEach(Array(protocols.enumerated()), id: \.element.id) { index, protocol_ in
                NavigationLink(value: protocol_) {
                    ProtocolCard(protocol_: protocol_)
                }
                .buttonStyle(.plain)
                .staggeredAppear(index: index)
            }
        }
    }
}

#Preview {
    ProtocolListView()
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
