import SwiftUI

struct StackLibraryView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var searchText = ""
    @State private var selectedTag: String?

    private var rankedStacks: [CommunityStack] {
        CommunityStackService.shared.ranked()
    }

    private var filteredStacks: [CommunityStack] {
        var result = rankedStacks
        if let selectedTag {
            result = result.filter { $0.goalTags.contains(selectedTag) }
        }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty {
            result = result.filter { stack in
                stack.name.lowercased().contains(trimmed)
                    || stack.authorName.lowercased().contains(trimmed)
                    || (stack.authorHandle?.lowercased().contains(trimmed) ?? false)
                    || stack.peptideAbbreviations.contains { $0.lowercased().contains(trimmed) }
            }
        }
        return result
    }

    private var featuredStacks: [CommunityStack] {
        rankedStacks.filter(\.featured)
    }

    private var goalTags: [String] {
        CommunityStackService.shared.allGoalTags
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                GlassTextField(
                    placeholder: "Search stacks, authors, peptides...",
                    text: $searchText
                )
                .padding(.horizontal, Spacing.screenPadding)

                tagChips
                    .padding(.horizontal, Spacing.screenPadding)

                if searchText.isEmpty && selectedTag == nil && !featuredStacks.isEmpty {
                    featuredCarousel
                }

                LazyVStack(spacing: Spacing.md) {
                    ForEach(filteredStacks) { stack in
                        NavigationLink(value: stack) {
                            CommunityStackCard(stack: stack)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)

                if filteredStacks.isEmpty {
                    emptyState
                        .padding(.top, Spacing.xxxl)
                }
            }
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxxxl)
        }
        .background(AppColor.background)
        .navigationTitle("Community Stacks")
        .navigationDestination(for: CommunityStack.self) { stack in
            CommunityStackDetailView(stack: stack)
        }
    }

    private var tagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                tagChip(label: "All", isSelected: selectedTag == nil) {
                    selectedTag = nil
                }
                ForEach(goalTags, id: \.self) { tag in
                    tagChip(label: tag, isSelected: selectedTag == tag) {
                        selectedTag = (selectedTag == tag) ? nil : tag
                    }
                }
            }
        }
    }

    private func tagChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(AppFont.caption)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? AppColor.accentLight : AppColor.textSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(
                    Capsule()
                        .fill(isSelected ? AppColor.glassTint : AppColor.cardOverlay)
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    isSelected ? AppColor.glassBorderActive : AppColor.glassBorder,
                                    lineWidth: 0.5
                                )
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var featuredCarousel: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("FEATURED")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
                .tracking(1.5)
                .padding(.horizontal, Spacing.screenPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    ForEach(featuredStacks) { stack in
                        NavigationLink(value: stack) {
                            CommunityStackCard(stack: stack)
                                .frame(width: 300)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(AppColor.textTertiary)
            Text("No stacks match")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textSecondary)
            Text("Try a different search term or clear the filter.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.screenPadding)
    }
}

#Preview {
    NavigationStack {
        StackLibraryView()
    }
    .environment(DataStore(seedSampleData: true))
    .preferredColorScheme(.dark)
}
