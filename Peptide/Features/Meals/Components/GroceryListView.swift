import SwiftUI

/// The shopping list for the planned day, scaled to 1, 3 or 7 days and
/// grouped by store section. Ticking a row sinks it to the bottom of its
/// section; "Clear checked" puts ticked rows away; Share sends what's
/// left to buy as plain text.
struct GroceryListView: View {
    let plan: MealPlanEngine.Plan

    @AppStorage("groceryList.days") private var days = 7
    @State private var store = GroceryChecklistStore.shared

    private static let dayOptions = [1, 3, 7]

    private var items: [GroceryListEngine.Item] {
        GroceryListEngine.items(from: GroceryListEngine.ingredients(from: plan, days: days))
    }

    private var groups: [GroceryListEngine.Group] {
        GroceryListEngine.groups(items.filter { !store.cleared.contains($0.key) })
    }

    private var remainingCount: Int {
        groups.reduce(0) { total, group in
            total + group.items.filter { !store.checked.contains($0.key) }.count
        }
    }

    private var hasChecked: Bool {
        groups.contains { group in group.items.contains { store.checked.contains($0.key) } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                if groups.isEmpty {
                    allDone
                } else {
                    ForEach(groups) { group in
                        sectionCard(group)
                    }
                    if hasChecked {
                        GlassButton(title: "Clear checked", icon: "checkmark.circle.badge.xmark", style: .secondary,
                                    isFullWidth: true, action: clearChecked)
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.lg)
            .readableContentWidth()
            .appAnimation(AppAnimation.springSnappy, value: days)
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("Shopping list")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: GroceryListEngine.plainText(groups, checked: store.checked)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(AppFont.scaled(16, weight: .semibold))
                }
                .disabled(remainingCount == 0)
                .accessibilityLabel("Share list")
            }
        }
        .onAppear { store.retain(Set(items.map(\.key))) }
        // Ticks are per quantity: 1 day's milk bought isn't 7 days' worth.
        .onChange(of: days) { store.startOver() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(remainingCount) to buy")
                    .font(AppFont.title2)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "cart.fill")
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .accessibilityHidden(true)
            }
            Text("Your planned day, bought for the days you pick.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            GlassSegmentedControl(
                options: Self.dayOptions,
                selected: $days,
                label: dayLabel
            )
        }
        .padding(Spacing.cardPadding)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    private func dayLabel(_ days: Int) -> LocalizedStringKey {
        switch days {
        case 1: "1 day"
        case 3: "3 days"
        default: "7 days"
        }
    }

    // MARK: - Sections

    private func sectionCard(_ group: GroceryListEngine.Group) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label(group.section.title, systemImage: group.section.icon)
                .font(AppFont.eyebrow)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.textSecondary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: Spacing.xs) {
                ForEach(GroceryListEngine.arranged(group.items, checked: store.checked)) { item in
                    GroceryRow(item: item, isChecked: store.checked.contains(item.key)) {
                        toggle(item)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        .padding(Spacing.cardPadding)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        .transition(.opacity)
        .scrollReveal()
    }

    private var allDone: some View {
        EmptyStateView(
            icon: "checkmark.seal.fill",
            title: "All done",
            message: "Everything on the list is ticked off.",
            action: .init(title: "Start over", icon: "arrow.counterclockwise", perform: startOver),
            style: .compact
        )
    }

    // MARK: - Actions

    private func toggle(_ item: GroceryListEngine.Item) {
        let checking = !store.checked.contains(item.key)
        AppAnimation.with(AppAnimation.springSnappy) {
            store.toggle(item.key)
        }
        if checking {
            Haptics.impact(.light)
        } else {
            Haptics.selection()
        }
    }

    private func clearChecked() {
        AppAnimation.with(AppAnimation.settle) {
            store.clearChecked()
        }
        Haptics.success()
    }

    private func startOver() {
        AppAnimation.with(AppAnimation.springSnappy) {
            store.startOver()
        }
        Haptics.selection()
    }
}

private struct GroceryRow: View {
    let item: GroceryListEngine.Item
    let isChecked: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Spacing.md) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(AppFont.scaled(20, weight: .medium))
                    .foregroundStyle(isChecked ? AppColor.positive : AppColor.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isChecked)
                Text(item.name)
                    .font(AppFont.body)
                    .strikethrough(isChecked, color: AppColor.textTertiary)
                    .foregroundStyle(isChecked ? AppColor.textTertiary : AppColor.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: Spacing.sm)
                Text(item.quantityText)
                    .font(AppFont.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(isChecked ? AppColor.textTertiary : AppColor.textSecondary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(minHeight: Spacing.minimumHitTarget)
            .insetRowBackground(cornerRadius: Spacing.smallCornerRadius)
            .contentShape(.rect)
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(item.name), \(item.quantityText)"))
        .accessibilityAddTraits(isChecked ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isChecked ? Text("Double-tap to put back on the list") : Text("Double-tap to tick off"))
    }
}
