import SwiftUI

struct PeptideSelector: View {
    @Binding var selectedPeptides: Set<UUID>
    var allPeptides: [Peptide]
    var onAddCustomPeptide: ((Peptide) -> Void)?
    @State private var searchText = ""
    @State private var selectedCategory: PeptideCategory?
    @State private var showSelectedOnly = false
    @State private var showCustomForm = false
    /// The unfiltered list is the whole database (200+ rows) inline in the
    /// builder's scroll, so it starts collapsed to a short preview.
    @State private var showAll = false

    private static let previewCount = 8

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

        let query = searchText
        result = result.filter { $0.matchesSearch(query) }

        return result
    }

    private var isCollapsed: Bool {
        !showAll && searchText.isEmpty && selectedCategory == nil && !showSelectedOnly
    }

    /// The first few rows plus anything already selected further down, so a
    /// pick never disappears behind the disclosure — and rows never reorder
    /// when toggled.
    private func visiblePeptides(from filtered: [Peptide]) -> [Peptide] {
        guard isCollapsed, filtered.count > Self.previewCount else { return filtered }
        let head = filtered.prefix(Self.previewCount)
        let headIDs = Set(head.map(\.id))
        let selectedTail = filtered.dropFirst(Self.previewCount).filter {
            selectedPeptides.contains($0.id) && !headIDs.contains($0.id)
        }
        return Array(head) + selectedTail
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            searchBar

            categoryFilters

            selectionSummary

            let filtered = filteredPeptides
            if filtered.isEmpty {
                emptyState
            } else {
                let visible = visiblePeptides(from: filtered)
                LazyVStack(spacing: Spacing.xs) {
                    ForEach(visible) { peptide in
                        peptideRow(peptide)
                    }
                }

                if visible.count < filtered.count {
                    Button {
                        AppAnimation.with(AppAnimation.springSnappy) { showAll = true }
                    } label: {
                        Text("Show all (\(filtered.count))")
                            .font(AppFont.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.accentLight)
                            .frame(maxWidth: .infinity)
                            .minimumHitArea()
                    }
                    .buttonStyle(ScalePressStyle())
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
            .liquidGlassPresentation()
        }
    }

    private var addCustomButton: some View {
        Button {
            showCustomForm = true
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Add your own compound")
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
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
        .buttonStyle(ScalePressStyle())
        .padding(.top, Spacing.xs)
    }

    private var searchBar: some View {
        GlassTextField(placeholder: "Search compounds", text: $searchText)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
    }

    private var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                GlassChip(
                    "All",
                    icon: "square.grid.2x2",
                    isSelected: selectedCategory == nil && !showSelectedOnly
                ) {
                    AppAnimation.with(AppAnimation.springSnappy) {
                        selectedCategory = nil
                        showSelectedOnly = false
                    }
                }

                if !selectedPeptides.isEmpty {
                    GlassChip(
                        "Selected",
                        icon: "checkmark.circle.fill",
                        isSelected: showSelectedOnly
                    ) {
                        AppAnimation.with(AppAnimation.springSnappy) {
                            showSelectedOnly.toggle()
                            if showSelectedOnly {
                                selectedCategory = nil
                            }
                        }
                    }
                }

                ForEach(availableCategories) { category in
                    GlassChip(
                        category.localizedTitle,
                        icon: category.iconName,
                        tint: category.color,
                        isSelected: selectedCategory == category
                    ) {
                        AppAnimation.with(AppAnimation.springSnappy) {
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
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.accentPrimary)
                Spacer()
                Button {
                    AppAnimation.with(AppAnimation.springSnappy) {
                        selectedPeptides.removeAll()
                    }
                } label: {
                    Text("Clear")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                        .minimumHitArea()
                }
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No compounds match",
            message: "Try a different search or filter.",
            action: addCustomAction,
            style: .compact
        )
        .frame(maxWidth: .infinity)
    }

    private var addCustomAction: EmptyStateView.Action? {
        guard onAddCustomPeptide != nil else { return nil }
        return EmptyStateView.Action(title: "Add your own", icon: "plus") {
            showCustomForm = true
        }
    }

    private func peptideRow(_ peptide: Peptide) -> some View {
        Button {
            Haptics.selection()
            AppAnimation.with(AppAnimation.springSnappy) {
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
                    .font(AppFont.scaled(20))
                    .foregroundStyle(isSelected ? AppColor.accentPrimary : AppColor.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)

                Image(systemName: peptide.imageSystemName)
                    .font(AppFont.scaled(13))
                    .foregroundStyle(peptide.category.color)
                    .frame(width: 28, height: 28)
                    .background {
                        RoundedRectangle(cornerRadius: Spacing.iconCornerRadius, style: .continuous)
                            .fill(peptide.category.color.opacity(0.15))
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(peptide.abbreviation)
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)

                    Text(peptide.category.localizedTitle)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textTertiary)
                }

                Spacer()
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
        .buttonStyle(ScalePressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selectedPeptides.contains(peptide.id) ? .isSelected : [])
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
