import SwiftUI

struct PeptideListView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var viewModel = PeptideListViewModel(peptides: PeptideDatabase.shared)
    @State private var showCustomForm = false

    private func refreshPeptides() {
        viewModel.updatePeptides(dataStore.peptideDatabase)
    }

    var body: some View {
        NavigationStack {
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
                        VStack(spacing: Spacing.md) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 36))
                                .foregroundStyle(AppColor.textTertiary)

                            Text("No peptides found")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textSecondary)

                            if !viewModel.searchText.isEmpty {
                                Text("Try a different search term")
                                    .font(AppFont.subheadline)
                                    .foregroundStyle(AppColor.textTertiary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.xxxxl)
                    } else {
                        LazyVStack(spacing: Spacing.md) {
                            ForEach(viewModel.filteredPeptides) { peptide in
                                NavigationLink(value: peptide) {
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
            .background(AppColor.background)
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
            .onAppear { refreshPeptides() }
        }
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
        .buttonStyle(.plain)
        .accessibilityLabel("Add custom peptide or pill")
        .accessibilityHint("Opens a form to add a custom peptide, drug, or supplement")
    }
}

#Preview {
    PeptideListView()
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
