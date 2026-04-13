import SwiftUI

struct PeptideListView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var viewModel = PeptideListViewModel()

    private func refreshPeptides() {
        viewModel.updatePeptides(dataStore.peptideDatabase)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
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
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Spacing.screenPadding)
                        .animation(AppAnimation.fadeIn, value: viewModel.filteredPeptides.map(\.id))
                    }
                }
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
            .onAppear { refreshPeptides() }
        }
    }
}

#Preview {
    PeptideListView()
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
