import SwiftUI

struct PeptideListView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var viewModel = PeptideListViewModel(peptides: PeptideDatabase.shared)
    @State private var showCustomForm = false
    @State private var selectedPeptide: Peptide?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private func refreshPeptides() {
        viewModel.updatePeptides(dataStore.peptideDatabase)
    }

    var body: some View {
        // NavigationSplitView gives iPad landscape a proper two-column layout
        // (peptide list on the left, selected peptide detail on the right)
        // while collapsing to a single-column stack on iPhone and iPad
        // portrait. Selection is bound to `selectedPeptide` so detail tracks
        // both row taps and external set (e.g. deep link).
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
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

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
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
                    hapticEnabled: dataStore.profile.hapticFeedbackEnabled,
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
                            Button {
                                selectedPeptide = peptide
                                if dataStore.profile.hapticFeedbackEnabled {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                }
                            } label: {
                                PeptideRow(peptide: peptide)
                            }
                            .buttonStyle(ScalePressStyle(pressedScale: 0.98))
                            .transition(.scale(scale: 0.97).combined(with: .opacity))
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
        .navigationTitle("Peptides")
        .toolbar {
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
        .sheet(isPresented: $showCustomForm) {
            CustomPeptideForm { peptide in
                dataStore.addCustomPeptide(peptide)
                refreshPeptides()
            }
            .liquidGlassPresentation()
        }
        .onAppear { refreshPeptides() }
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
