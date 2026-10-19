import SwiftUI

struct StackLibraryView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @State private var selectedTag: String?
    /// The bundled catalogue never changes while the screen is up, so it's
    /// ranked once rather than re-sorted on every body pass and keystroke.
    @State private var rankedStacks: [CommunityStack]
    @State private var goalTags: [String]

    init() {
        let service = CommunityStackService.shared
        _rankedStacks = State(initialValue: service.ranked())
        _goalTags = State(initialValue: service.allGoalTags)
    }

    private var isShowingCarousel: Bool {
        searchText.isEmpty && selectedTag == nil && !featuredStacks.isEmpty
    }

    private var filteredStacks: [CommunityStack] {
        // Featured stacks already sit in the carousel above; listing them
        // again straight underneath read as a duplicate.
        var result = isShowingCarousel ? rankedStacks.filter { !$0.featured } : rankedStacks
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

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                GlassTextField(
                    placeholder: "Search stacks, peptides…",
                    text: $searchText
                )
                .padding(.horizontal, Spacing.screenPadding)

                tagChips
                    .padding(.horizontal, Spacing.screenPadding)

                if isShowingCarousel {
                    featuredCarousel
                }

                let stacks = filteredStacks
                LazyVStack(spacing: Spacing.md) {
                    ForEach(Array(stacks.enumerated()), id: \.element.id) { index, stack in
                        NavigationLink(value: stack) {
                            CommunityStackCard(stack: stack)
                        }
                        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
                        .staggeredAppear(index: index)
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)

                if stacks.isEmpty && !isShowingCarousel {
                    emptyState
                        .padding(.top, Spacing.xxxl)
                }
            }
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxxxl)
        }
        .background(AppColor.background)
        .navigationTitle("Stack Library")
        // The `CommunityStack` navigation destination is declared by
        // every host stack that pushes this view (ProtocolListView,
        // ProtocolBuilderView). Declaring it again here collides on
        // the same stack — SwiftUI ignores one and the behaviour is
        // undefined — so it is intentionally omitted.
    }

    private var tagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                GlassChip("All", isSelected: selectedTag == nil) {
                    AppAnimation.with(AppAnimation.springSnappy) { selectedTag = nil }
                }
                ForEach(goalTags, id: \.self) { tag in
                    GlassChip(LocalizedStringKey(tag), isSelected: selectedTag == tag) {
                        AppAnimation.with(AppAnimation.springSnappy) {
                            selectedTag = (selectedTag == tag) ? nil : tag
                        }
                    }
                }
            }
        }
    }

    private var featuredCarousel: some View {
        // Captured as a value: the scroll-transition closure is @Sendable.
        let shrinks = !reduceMotion
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HomeSectionHeader(eyebrow: "Featured", title: "Editor's picks")
                .padding(.horizontal, Spacing.screenPadding)

            // Paged, snapping carousel: one card per page with the next
            // peeking in, and off-centre cards eased back.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    ForEach(featuredStacks) { stack in
                        NavigationLink(value: stack) {
                            CommunityStackCard(stack: stack)
                        }
                        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
                        .containerRelativeFrame(.horizontal) { length, _ in length * 0.86 }
                        .scrollTransition { card, phase in
                            card
                                .scaleEffect(shrinks && !phase.isIdentity ? 0.94 : 1)
                                .opacity(phase.isIdentity ? 1 : 0.7)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Spacing.screenPadding, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No stacks match",
            message: "Try a different search term or clear the filter.",
            action: .init(title: "Clear filters", icon: "xmark.circle.fill") {
                AppAnimation.with(AppAnimation.springSnappy) {
                    searchText = ""
                    selectedTag = nil
                }
            }
        )
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
