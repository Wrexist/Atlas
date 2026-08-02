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

    var body: some View {
        @Bindable var state = appState

        NavigationStack(path: $path) {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        CommunityStacksEntryCard()

                        if dataStore.protocols.isEmpty {
                            EmptyStateView(
                                icon: "list.clipboard",
                                title: "No Protocols Yet",
                                message: "Create your first peptide protocol to start tracking your regimen.",
                                action: .init(title: "Create Protocol", icon: "plus") {
                                    Haptics.impact(.medium)
                                    showingBuilder = true
                                }
                            )
                            .padding(.top, Spacing.xxl)
                            .sectionAppear(index: 0)
                        } else {
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
                                    title: "Active",
                                    protocols: dataStore.activeProtocols,
                                    onShare: { sharingProtocol = $0 }
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
                                    title: "Paused",
                                    protocols: dataStore.pausedProtocols,
                                    onShare: { sharingProtocol = $0 }
                                )
                                .sectionAppear(index: 5)
                            }

                            if !dataStore.completedProtocols.isEmpty {
                                ProtocolSection(
                                    title: "Completed",
                                    protocols: dataStore.completedProtocols,
                                    onShare: { sharingProtocol = $0 }
                                )
                                .sectionAppear(index: 6)
                            }
                        }
                    }
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
                    } else {
                        Haptics.impact(.medium)
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .navigationDestination(for: PeptideProtocol.self) { protocol_ in
                ProtocolDetailView(protocol_: protocol_)
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
                PaywallView()
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

private struct CommunityStacksEntryCard: View {
    var body: some View {
        NavigationLink(value: StackLibraryRoute()) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .fill(AppColor.accentPrimary.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "books.vertical.fill")
                        .font(AppFont.scaled(16, weight: .bold))
                        .foregroundStyle(AppColor.accentLight)
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Browse community stacks")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Research-backed templates from peptide practitioners")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.6))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .fill(AppColor.glassTint)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Browse community stacks")
    }
}

private struct ProtocolSection: View {
    let title: String
    let protocols: [PeptideProtocol]
    let onShare: (PeptideProtocol) -> Void

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
                .contextMenu {
                    Button {
                        onShare(protocol_)
                    } label: {
                        Label("Share Cycle Card", systemImage: "square.and.arrow.up")
                    }
                }
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
