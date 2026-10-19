import SwiftUI

struct PeptideListView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss
    /// True when opened as the demoted Library modal (from Today's cycle
    /// pill or a Profile entry via `AppState.showLibrary`) — adds a Done
    /// button. False when hosted directly.
    var presentedModally = false
    @State private var viewModel = PeptideListViewModel(peptides: PeptideDatabase.shared)
    @State private var showCustomForm = false
    /// Ties each row to the detail view it pushes, so the push grows out of
    /// the tapped row instead of sliding in over it. Only the iPhone stack
    /// uses it — the iPad split view swaps the detail column in place and has
    /// no push to animate.
    @Namespace private var zoom

    /// Built here rather than inline: a ternary whose branches are both
    /// trailing-closure `.init`s is a parse hazard, and the empty state
    /// should always offer whichever escape actually applies.
    private var noResultsAction: EmptyStateView.Action {
        if viewModel.searchText.isEmpty {
            return EmptyStateView.Action(title: "Add custom peptide",
                                         icon: "plus.circle.fill") {
                showCustomForm = true
            }
        }
        return EmptyStateView.Action(title: "Clear search",
                                     icon: "xmark.circle.fill") {
            viewModel.searchText = ""
        }
    }
    @State private var showResearchAssistant = false
    @State private var selectedPeptide: Peptide?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var storeService = StoreService.shared
    @State private var showPaywall = false
    /// Presents `ProtocolListView` over the Library when set. Driven
    /// by `AppState.pendingProtocolList` so call sites that
    /// historically jumped to the (now demoted) Protocols tab land
    /// the user on the protocols screen in one hop.
    @State private var showProtocols = false

    private func refreshPeptides() {
        viewModel.updatePeptides(dataStore.peptideDatabase)
        // Clear the iPad detail selection if the selected peptide is no
        // longer in the list (e.g. a custom peptide deleted or removed
        // by a CloudKit sync) — otherwise the detail pane keeps showing
        // a ghost record that's gone from the sidebar.
        if let selected = selectedPeptide,
           !viewModel.allPeptides.contains(where: { $0.id == selected.id }) {
            selectedPeptide = nil
        }
    }

    var body: some View {
        // On iPhone (or iPad portrait), NavigationStack with NavigationLink
        // gives the standard push-to-detail behavior users expect from a
        // list. On iPad regular, NavigationSplitView yields a true two-pane
        // layout with the detail kept in sync via `selectedPeptide`.
        //
        // We branch on size class instead of relying on NavigationSplitView's
        // own collapse — the collapsed form swallows NavigationLink(value:)
        // pushes when the row tap only sets a selection binding (Codex
        // review on PR #99 caught this; iPhone users were stranded on the
        // list with no way into the detail).
        Group {
            if sizeClass == .regular {
                iPadSplitLayout
            } else {
                iPhoneStackLayout
            }
        }
        .onAppear {
            refreshPeptides()
            consumePendingProtocolList()
        }
        .onChange(of: appState.pendingProtocolList) { _, newValue in
            if newValue { consumePendingProtocolList() }
        }
        // ProtocolListView owns its own NavigationStack, so it's
        // presented as a plain sheet — wrapping it in another stack (the
        // old fullScreenCover) nested two stacks and forced a hand-rolled
        // "Close". A sheet gives native swipe-to-dismiss + a Done button
        // and matches how every other surface is presented.
        .sheet(isPresented: $showProtocols) {
            ProtocolListView()
                .liquidGlassPresentation()
        }
        .sheet(isPresented: $showCustomForm) {
            CustomPeptideForm { peptide in
                dataStore.addCustomPeptide(peptide)
                refreshPeptides()
            }
            .liquidGlassPresentation()
        }
        .sheet(isPresented: $showResearchAssistant) {
            AIResearchView()
                .environment(dataStore)
                .liquidGlassPresentation()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: .aiResearch)
                .environment(dataStore)
                .liquidGlassPresentation()
        }
    }

    /// One-shot: when the AppState flag is set, present the protocol
    /// list and immediately clear the flag so a subsequent
    /// `onAppear` doesn't re-trigger.
    private func consumePendingProtocolList() {
        guard appState.pendingProtocolList else { return }
        showProtocols = true
        appState.pendingProtocolList = false
    }

    // MARK: - iPad split layout

    private var iPadSplitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent(useNavigationLinks: false)
                .navigationTitle("Library")
                .toolbar { sidebarToolbar }
        } detail: {
            NavigationStack {
                if let selectedPeptide {
                    PeptideDetailView(peptide: selectedPeptide)
                        .navigationDestination(for: Peptide.self) { peptide in
                            PeptideDetailView(peptide: peptide)
                        }
                } else {
                    EmptyStateView(
                        icon: "flask",
                        title: "Pick a Peptide",
                        message: "Select a peptide from the list to see its research, dosing, and protocol ideas."
                    )
                    .padding(Spacing.screenPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColor.background)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - iPhone stack layout

    private var iPhoneStackLayout: some View {
        NavigationStack {
            sidebarContent(useNavigationLinks: true)
                .navigationTitle("Library")
                .toolbar { sidebarToolbar }
                .navigationDestination(for: Peptide.self) { peptide in
                    PeptideDetailView(peptide: peptide)
                        .navigationTransition(.zoom(sourceID: peptide.id, in: zoom))
                }
        }
    }

    // MARK: - Shared sidebar content

    /// `useNavigationLinks=true` on iPhone routes taps through the
    /// NavigationStack's `.navigationDestination(for:)`. On iPad regular we
    /// instead set `selectedPeptide` directly so the right detail pane
    /// updates without a push.
    private func sidebarContent(useNavigationLinks: Bool) -> some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // New-user CTA only: once a protocol exists the toolbar's
                // Protocols button is the way back in, so the card would
                // just push the list further down.
                if dataStore.activeProtocols.isEmpty {
                    ProtocolsEntryCard(onTap: { showProtocols = true })
                        .padding(.horizontal, Spacing.screenPadding)
                }

                CategoryFilterChips(
                    categories: viewModel.categories,
                    selected: viewModel.selectedCategory,
                    onSelect: viewModel.selectCategory
                )

                if viewModel.filteredPeptides.isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No peptides found",
                        message: viewModel.searchText.isEmpty
                            ? "Add a custom peptide to start building protocols."
                            : "Try a different search term.",
                        // The copy already tells the user what to do next;
                        // without this it was the only way to do it.
                        action: noResultsAction
                    )
                    .padding(.top, Spacing.xl)
                } else {
                    LazyVStack(spacing: Spacing.md) {
                        ForEach(viewModel.filteredPeptides) { peptide in
                            peptideRow(peptide, useNavigationLink: useNavigationLinks)
                        }
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                    .appAnimation(AppAnimation.fadeIn, value: viewModel.filteredPeptides.map(\.id))

                    // Invites a compound, drug, or pill not in the database.
                    GlassEntryRow(
                        icon: "plus",
                        title: "Add your own compound",
                        subtitle: Text("Anything not in the database — peptides, drugs, supplements"),
                        action: { showCustomForm = true }
                    )
                    .accessibilityHint("Opens a form to add a custom peptide, drug, or supplement")
                    .padding(.horizontal, Spacing.screenPadding)
                }
            }
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxxxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColor.background)
        // Pinned under the title so search stays reachable however far
        // down the list the user has scrolled.
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search compounds"
        )
        .refreshable {
            // The peptide database is in-memory, so refresh just re-pulls
            // any custom peptides the user added on another device via
            // iCloud sync and re-applies the active filter.
            refreshPeptides()
        }
    }

    @ViewBuilder
    private func peptideRow(_ peptide: Peptide, useNavigationLink: Bool) -> some View {
        if useNavigationLink {
            NavigationLink(value: peptide) {
                PeptideRow(peptide: peptide)
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.98))
            .matchedTransitionSource(id: peptide.id, in: zoom)
            .transition(.scale(scale: 0.97).combined(with: .opacity))
        } else {
            Button {
                selectedPeptide = peptide
                Haptics.selection()
            } label: {
                PeptideRow(peptide: peptide)
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.98))
            .transition(.scale(scale: 0.97).combined(with: .opacity))
        }
    }

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        if presentedModally {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
                    .accessibilityLabel("Close Library")
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            Button {
                if storeService.isProUser {
                    showResearchAssistant = true
                } else {
                    showPaywall = true
                }
            } label: {
                Label("Ask the assistant", systemImage: "sparkles")
                    .labelStyle(.iconOnly)
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
            }
            .accessibilityLabel("Open AI research assistant")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showProtocols = true
            } label: {
                Label("Protocols", systemImage: "square.stack.3d.up.fill")
                    .labelStyle(.iconOnly)
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
            }
            .accessibilityLabel("Open protocols")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showCustomForm = true
            } label: {
                Label("Add your own compound", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
            }
            .accessibilityLabel("Add your own compound")
        }
    }
}

/// Top-of-Library new-user CTA into protocols (moved off the Today tab).
private struct ProtocolsEntryCard: View {
    let onTap: () -> Void

    var body: some View {
        GlassEntryRow(
            icon: "list.clipboard.fill",
            title: "Create your first protocol",
            subtitle: Text("Track what you take and how consistent you are."),
            badge: Badge("Get started", style: .solid),
            action: onTap
        )
    }
}

#Preview {
    PeptideListView()
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
