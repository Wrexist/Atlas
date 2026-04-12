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

                    LazyVStack(spacing: Spacing.md) {
                        ForEach(Array(viewModel.filteredPeptides.enumerated()), id: \.element.id) { index, peptide in
                            NavigationLink(value: peptide) {
                                PeptideRow(peptide: peptide)
                            }
                            .buttonStyle(.plain)
                            .staggeredAppear(index: index)
                        }
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                }
                .padding(.bottom, Spacing.xxxxl)
            }
            .background(AppColor.background)
            .navigationTitle("Peptides")
            .navigationDestination(for: Peptide.self) { peptide in
                PeptideDetailView(peptide: peptide)
            }
            .onAppear { refreshPeptides() }
        }
    }
}

#Preview {
    PeptideListView()
        .environment(DataStore())
        .preferredColorScheme(.dark)
}
