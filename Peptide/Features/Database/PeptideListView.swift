import SwiftUI

struct PeptideListView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var viewModel = PeptideListViewModel(peptides: PeptideDatabase.shared)
    @State private var showCustomForm = false
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
        .fullScreenCover(isPresented: $showProtocols) {
            NavigationStack {
                ProtocolListView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { showProtocols = false }
                        }
                    }
            }
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
                }
                .sheet(isPresented: $showPaywall) {
                    PaywallView()
                        .environment(dataStore)
                        .liquidGlassPresentation()
                }
        } detail: {
            NavigationStack {
                if let selectedPeptide {
                    PeptideDetailView(peptide: selectedPeptide)
                } else {
                    EmptyStateView(
                        icon: "flask",
                        title: "Pick a Peptide",
                        message: "Select a peptide from the list to see its research, dosing, and stack ideas."
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
                }
                .sheet(isPresented: $showPaywall) {
                    PaywallView()
                        .environment(dataStore)
                        .liquidGlassPresentation()
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
                // Protocol creation lives here now (moved off Today).
                // Reads as the primary CTA for a new user with no
                // protocols, then collapses to a compact "manage"
                // entry once they have one.
                ProtocolsEntryCard(
                    activeCount: dataStore.activeProtocols.count,
                    onTap: { showProtocols = true }
                )
                .padding(.horizontal, Spacing.screenPadding)

                AddCustomPeptideCard {
                    showCustomForm = true
                }
                .padding(.horizontal, Spacing.screenPadding)

                GlassTextField(
                    placeholder: "Search peptides...",
                    text: $viewModel.searchText
                )
                .padding(.horizontal, Spacing.screenPadding)

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
                            : "Try a different search term."
                    )
                    .padding(.top, Spacing.xl)
                } else {
                    LazyVStack(spacing: Spacing.md) {
                        ForEach(viewModel.filteredPeptides) { peptide in
                            peptideRow(peptide, useNavigationLink: useNavigationLinks)
                        }
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                    .animation(AppAnimation.fadeIn, value: viewModel.filteredPeptides.map(\.id))
                }
            }
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxxxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColor.background)
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
                    .font(.system(size: 16, weight: .semibold))
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
            }
            .accessibilityLabel("Open protocols")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Text("\(viewModel.allPeptides.count)")
                .font(AppFont.caption)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.accentPrimary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxs)
                .background {
                    Capsule()
                        .fill(AppColor.accentPrimary.opacity(0.15))
                }
        }
    }
}

/// Top-of-Library entry into protocols. Doubles as the new-user
/// "create your first protocol" CTA (this moved off the Today tab) and,
/// once protocols exist, a compact way back into the protocol list.
private struct ProtocolsEntryCard: View {
    let activeCount: Int
    let onTap: () -> Void

    private var isEmpty: Bool { activeCount == 0 }

    private var title: LocalizedStringKey {
        isEmpty ? "Create your first protocol" : "Your protocols"
    }

    private var subtitle: String {
        if isEmpty {
            return String(localized: "Track doses, streaks, and compliance.")
        }
        return activeCount == 1
            ? String(localized: "1 active · tap to manage")
            : String(format: String(localized: "%d active · tap to manage"), activeCount)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(AppColor.accentPrimary.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "flask.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppColor.accentLight)
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer()

                if isEmpty {
                    Text("Get started")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(AppColor.accentPrimary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.accentPrimary.opacity(isEmpty ? 0.12 : 0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(
                                isEmpty ? AppColor.accentPrimary.opacity(0.45) : AppColor.glassBorder,
                                lineWidth: isEmpty ? 1 : 0.5
                            )
                    }
            }
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel(isEmpty ? "Create your first protocol" : "Open your protocols")
    }
}

/// Prominent affordance at the top of the Peptides tab inviting the user to
/// add a custom peptide, drug, or pill not in the database.
private struct AddCustomPeptideCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .fill(AppColor.accentPrimary.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppColor.accentLight)
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Add Custom Peptide or Pill")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Add anything not in the database — peptides, drugs, supplements")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
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
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel("Add custom peptide or pill")
        .accessibilityHint("Opens a form to add a custom peptide, drug, or supplement")
    }
}

#Preview {
    PeptideListView()
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
