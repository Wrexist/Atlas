import SwiftUI

struct PeptideSelector: View {
    @Binding var selectedPeptides: Set<UUID>
    var allPeptides: [Peptide]
    var onAddCustomPeptide: ((Peptide) -> Void)?
    @State private var searchText = ""
    @State private var selectedCategory: PeptideCategory?
    @State private var showSelectedOnly = false
    @State private var showCustomForm = false

    private var availableCategories: [PeptideCategory] {
        let present = Set(allPeptides.map(\.category))
        return PeptideCategory.allCases.filter { present.contains($0) }
    }

    private var filteredPeptides: [Peptide] {
        var result = allPeptides

        if showSelectedOnly {
            result = result.filter { selectedPeptides.contains($0.id) }
        }

        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.abbreviation.lowercased().contains(query) ||
                $0.category.displayName.lowercased().contains(query)
            }
        }

        return result
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            searchBar

            categoryFilters

            selectionSummary

            if filteredPeptides.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: Spacing.xs) {
                    ForEach(filteredPeptides) { peptide in
                        peptideRow(peptide)
                    }
                }
            }

            if onAddCustomPeptide != nil {
                addCustomButton
            }
        }
        .sheet(isPresented: $showCustomForm) {
            CustomPeptideForm { peptide in
                onAddCustomPeptide?(peptide)
                selectedPeptides.insert(peptide.id)
            }
        }
    }

    private var addCustomButton: some View {
        Button {
            showCustomForm = true
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Add Custom Peptide")
                    .font(AppFont.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundStyle(AppColor.accentPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(AppColor.accentPrimary.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .strokeBorder(
                                AppColor.accentPrimary.opacity(0.4),
                                style: StrokeStyle(lineWidth: 0.8, dash: [4, 3])
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .padding(.top, Spacing.xs)
    }

    private var searchBar: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(AppColor.textTertiary)

            TextField("Search peptides...", text: $searchText)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)
                .tint(AppColor.accentPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button {
                    withAnimation(AppAnimation.springSnappy) {
                        searchText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColor.textTertiary)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceElevated)
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
    }

    private var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                FilterChip(
                    title: "All",
                    icon: "square.grid.2x2",
                    color: AppColor.accentPrimary,
                    isSelected: selectedCategory == nil && !showSelectedOnly
                ) {
                    withAnimation(AppAnimation.springSnappy) {
                        selectedCategory = nil
                        showSelectedOnly = false
                    }
                }

                if !selectedPeptides.isEmpty {
                    FilterChip(
                        title: "Selected",
                        icon: "checkmark.circle.fill",
                        color: AppColor.accentPrimary,
                        isSelected: showSelectedOnly
                    ) {
                        withAnimation(AppAnimation.springSnappy) {
                            showSelectedOnly.toggle()
                            if showSelectedOnly {
                                selectedCategory = nil
                            }
                        }
                    }
                }

                ForEach(availableCategories) { category in
                    FilterChip(
                        title: category.localizedTitle,
                        icon: category.iconName,
                        color: category.color,
                        isSelected: selectedCategory == category
                    ) {
                        withAnimation(AppAnimation.springSnappy) {
                            selectedCategory = (selectedCategory == category) ? nil : category
                            showSelectedOnly = false
                        }
                    }
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 1)
        }
    }

    @ViewBuilder
    private var selectionSummary: some View {
        if !selectedPeptides.isEmpty {
            HStack {
                Text("\(selectedPeptides.count) selected")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.accentPrimary)
                Spacer()
                Button {
                    withAnimation(AppAnimation.springSnappy) {
                        selectedPeptides.removeAll()
                    }
                } label: {
                    Text("Clear")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(AppColor.textTertiary)
            Text("No peptides match")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            Text("Try a different search or filter")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }

    private func peptideRow(_ peptide: Peptide) -> some View {
        Button {
            withAnimation(AppAnimation.springSnappy) {
                if selectedPeptides.contains(peptide.id) {
                    selectedPeptides.remove(peptide.id)
                } else {
                    selectedPeptides.insert(peptide.id)
                }
            }
        } label: {
            let isSelected = selectedPeptides.contains(peptide.id)

            HStack(spacing: Spacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? AppColor.accentPrimary : AppColor.textTertiary)
                    .contentTransition(.symbolEffect(.replace))

                Image(systemName: peptide.imageSystemName)
                    .font(.system(size: 14))
                    .foregroundStyle(peptide.category.color)
                    .frame(width: 28, height: 28)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(peptide.category.color.opacity(0.15))
                    }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(peptide.abbreviation)
                        .font(AppFont.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(AppColor.textPrimary)

                    Text(peptide.category.localizedTitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }

                Spacer()

                Text(peptide.dosageRange)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
            }
            .padding(.vertical, Spacing.xs)
            .padding(.horizontal, Spacing.sm)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .fill(AppColor.accentPrimary.opacity(0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                .strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                        }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct FilterChip: View {
    let title: LocalizedStringKey
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(AppFont.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isSelected ? color : AppColor.textSecondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(isSelected ? color.opacity(0.18) : AppColor.surfaceElevated)
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                isSelected ? color.opacity(0.5) : AppColor.glassBorder,
                                lineWidth: 0.5
                            )
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        PeptideSelector(selectedPeptides: .constant([MockPeptides.bpc157.id]), allPeptides: MockPeptides.all)
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
