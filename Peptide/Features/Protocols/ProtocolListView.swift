import SwiftUI

struct ProtocolListView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState
    /// Set when presented as a sheet (its only call site today) so the
    /// root can offer a native Done button instead of a hand-rolled one
    /// on an enclosing stack.
    @Environment(\.dismiss) private var dismiss
    @State private var showingBuilder = false
    @State private var showingPaywall = false
    @State private var preselectedPeptide: Peptide?
    // Type-erased — this stack pushes three distinct value types
    // (PeptideProtocol, CommunityStack, StackLibraryRoute). A typed
    // `[PeptideProtocol]` binding couldn't represent the other two,
    // desyncing navigation state once a stack/library route was pushed.
    @State private var path = NavigationPath()
    @State private var sharingProtocol: PeptideProtocol?
    /// Shared with every ProtocolSection so a card's push grows out of
    /// the card itself. The sections are separate views, so the id has to
    /// travel down rather than being declared where the rows are.
    @Namespace private var zoom

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
                                message: "Build a protocol to track what you take, when, and how it's going.",
                                action: .init(title: "Create Protocol", icon: "plus") {
                                    Haptics.impact(.medium)
                                    showingBuilder = true
                                },
                                secondary: .init(title: "Browse the library", icon: "books.vertical") {
                                    path.append(StackLibraryRoute())
                                }
                            )
                            .padding(.top, Spacing.xxl)
                            .sectionAppear(index: 0)
                        } else {
                            NavigationLink(value: StackLibraryRoute()) {
                                GlassEntryRowLabel(
                                    icon: "books.vertical.fill",
                                    title: "Browse the protocol library",
                                    subtitle: Text("Ready-made templates you can start from")
                                )
                            }
                            .buttonStyle(ScalePressStyle(pressedScale: 0.98))

                            // Compact vial-shelf glance — "what
                            // compounds am I currently on?" — sits
                            // above the per-protocol detail list so
                            // the user reads the shape of the stack
                            // before drilling into individual rows.
                            VialShelfCard(peptides: dataStore.stackPeptides)
                                .sectionAppear(index: 0)

                            TrackCalendarSection(
                                entries: dataStore.entries,
                                protocols: dataStore.protocols,
                                activePeptides: dataStore.stackPeptides
                            )
                            .sectionAppear(index: 1)

                            if !dataStore.activeProtocols.isEmpty {
                                ProtocolSection(
                                    eyebrow: "Active",
                                    title: "Running now",
                                    protocols: dataStore.activeProtocols,
                                    onShare: { sharingProtocol = $0 },
                                    zoom: zoom
                                )
                                .sectionAppear(index: 2)
                            }

                            // Stack health + Discover sections moved
                            // here from HomeView in Phase 34. They
                            // live between Active and Paused so the
                            // user's eye lands on their current
                            // stack first, then the analytical
                            // metadata, then the older protocols.
                            ProtocolsStackHealthSection()
                                .sectionAppear(index: 3)

                            ProtocolsDiscoverSection()
                                .sectionAppear(index: 4)

                            if !dataStore.pausedProtocols.isEmpty {
                                ProtocolSection(
                                    eyebrow: "Paused",
                                    title: "On hold",
                                    protocols: dataStore.pausedProtocols,
                                    onShare: { sharingProtocol = $0 },
                                    zoom: zoom
                                )
                                .sectionAppear(index: 5)
                            }

                            if !dataStore.completedProtocols.isEmpty {
                                ProtocolSection(
                                    eyebrow: "Completed",
                                    title: "Finished cycles",
                                    protocols: dataStore.completedProtocols,
                                    onShare: { sharingProtocol = $0 },
                                    zoom: zoom
                                )
                                .sectionAppear(index: 6)
                            }
                        }
                    }
                    .appAnimation(AppAnimation.springSmooth, value: dataStore.protocols.map(\.status))
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.bottom, Spacing.scrollBottomInset)
                    // iPad content cap so the protocol list reads in
                    // a comfortable measure rather than stretching
                    // edge-to-edge (Phase 5.8 partial).
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                .background(AppColor.background)

                // Floating add button
                GlassIconButton(icon: "plus", accessibilityLabel: "New protocol", size: 56, tinted: true) {
                    preselectedPeptide = nil
                    let blocked = StoreService.shared.requiresPro(
                        activeProtocolCount: dataStore.activeProtocols.count
                    )
                    if blocked {
                        Haptics.warning()
                        showingPaywall = true
                    } else {
                        Haptics.impact(.medium)
                        showingBuilder = true
                    }
                }
                .appShadow(AppShadow.glassElevated)
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .navigationDestination(for: PeptideProtocol.self) { protocol_ in
                ProtocolDetailView(protocol_: protocol_)
                    .navigationTransition(.zoom(sourceID: protocol_.id, in: zoom))
            }
            // Registered here, once, so Protocol → Peptide → Protocol never
            // stacks a second `Peptide` declaration from a pushed view.
            .navigationDestination(for: Peptide.self) { peptide in
                PeptideDetailView(peptide: peptide)
            }
            .navigationDestination(for: CommunityStack.self) { stack in
                CommunityStackDetailView(stack: stack)
            }
            .navigationDestination(for: StackLibraryRoute.self) { _ in
                StackLibraryView()
            }
            .glassSheet(isPresented: $showingBuilder) {
                ProtocolBuilderView(preselectedPeptide: preselectedPeptide)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(source: .protocolLimit)
                    .liquidGlassPresentation()
            }
            .onAppear { consumePendingDeepLink() }
            .onChange(of: appState.pendingProtocolDeepLink) { _, _ in
                consumePendingDeepLink()
            }
            .sheet(item: $sharingProtocol) { proto in
                ShareCardSheet(subject: .singleProtocol(proto))
                    .liquidGlassPresentation()
            }
        }
    }

    /// Pushes the deep-linked protocol onto the navigation path if the
    /// user has it. The pending id is cleared immediately, so the two
    /// callers (`onAppear` + `onChange`) can't both consume the same
    /// value — no separate last-element dedup is needed (and
    /// `NavigationPath` is opaque, so element inspection isn't possible).
    private func consumePendingDeepLink() {
        guard let id = appState.pendingProtocolDeepLink,
              let target = dataStore.protocols.first(where: { $0.id == id })
        else { return }
        path.append(target)
        appState.pendingProtocolDeepLink = nil
    }
}

/// Token-only routing value used by the entry card so SwiftUI's
/// `NavigationLink(value:)` resolves to `StackLibraryView`.
struct StackLibraryRoute: Hashable {}

private struct ProtocolSection: View {
    let eyebrow: LocalizedStringKey
    let title: LocalizedStringKey
    let protocols: [PeptideProtocol]
    let onShare: (PeptideProtocol) -> Void
    let zoom: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HomeSectionHeader(eyebrow: eyebrow, title: title)

            ForEach(protocols) { protocol_ in
                NavigationLink(value: protocol_) {
                    ProtocolCard(protocol_: protocol_)
                }
                .buttonStyle(ScalePressStyle(pressedScale: 0.98))
                .matchedTransitionSource(id: protocol_.id, in: zoom)
                .contextMenu {
                    Button {
                        onShare(protocol_)
                    } label: {
                        Label("Share Cycle Card", systemImage: "square.and.arrow.up")
                    }
                }
                // Status changes animate at the list root, so a paused or
                // completed card glides between sections instead of popping.
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
    }
}

#Preview {
    ProtocolListView()
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
