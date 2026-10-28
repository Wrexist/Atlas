import SwiftUI

// MARK: - Dish

/// One of the week's dishes: the plate, its name and how many boxes it makes.
struct PrepDishCard: View {
    let recipe: LibraryRecipe
    let servings: Int
    /// After prep day the plan is fixed: no stepper, no swap.
    let isLocked: Bool
    let setServings: (Int) -> Void
    let swap: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            NavigationLink {
                RecipeDetailView(recipe: recipe)
            } label: {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    RecipeCutout(recipe: recipe)
                        .aspectRatio(1, contentMode: .fit)
                        .padding(.horizontal, Spacing.sm)
                    Text(recipe.displayName(locale: locale))
                        .font(AppFont.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                    Text("\(recipe.minutes) min · \(Int(recipe.proteinG.rounded())) g protein per box")
                        .font(AppFont.caption2)
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.97))

            if isLocked {
                Label("\(servings) boxes", systemImage: "shippingbox.fill")
                    .font(AppFont.chipText)
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(minHeight: Spacing.minimumHitTarget)
            } else {
                boxStepper
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        .overlay(alignment: .topTrailing) {
            if !isLocked {
                swapButton
                    .padding(Spacing.sm)
            }
        }
    }

    private var swapButton: some View {
        Button(action: swap) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .frame(width: 32, height: 32)
                .glassControl(.circle)
                .minimumHitArea()
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.9))
        .accessibilityLabel(Text("Swap dish"))
    }

    private var boxStepper: some View {
        HStack(spacing: Spacing.xs) {
            stepButton(icon: "minus", label: "Fewer boxes", delta: -1)
                .disabled(servings <= WeeklyPrepEngine.servingRange.lowerBound)
            Text("\(servings) boxes")
                .font(AppFont.chipText)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                .fixedSize()
                .accessibilityHidden(true)
            stepButton(icon: "plus", label: "More boxes", delta: 1)
                .disabled(servings >= WeeklyPrepEngine.servingRange.upperBound)
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(Text("\(servings) boxes"))
    }

    private func stepButton(icon: String, label: LocalizedStringKey, delta: Int) -> some View {
        Button {
            setServings(servings + delta)
        } label: {
            Image(systemName: icon)
                .font(AppFont.scaled(13, weight: .bold))
                .foregroundStyle(AppColor.accentLight)
                .frame(width: 28, height: 28)
                .glassControl(.circle)
                .minimumHitArea()
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.9))
        .accessibilityLabel(label)
    }
}

// MARK: - Shopping list

/// Both dishes' ingredients for the whole week, by store section. Tap to
/// tick off; what is already at home sits at the bottom of its section.
struct PrepShoppingCard: View {
    let items: [WeeklyPrepEngine.ShoppingItem]
    let bought: Set<String>
    let toggleBought: (WeeklyPrepEngine.ShoppingItem) -> Void
    let toggleAtHome: (WeeklyPrepEngine.ShoppingItem) -> Void

    @Environment(\.locale) private var locale

    private var toBuy: [WeeklyPrepEngine.ShoppingItem] {
        items.filter { !$0.isAtHome && !bought.contains($0.pantryKey) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            CardTitle(
                title: "Shopping list",
                subtitle: toBuy.isEmpty ? Text("All bought") : Text("\(toBuy.count) left to buy"),
                isDone: toBuy.isEmpty
            )
            ForEach(WeeklyPrepEngine.grouped(items)) { group in
                VStack(alignment: .leading, spacing: 0) {
                    Label(group.section.title, systemImage: group.section.icon)
                        .font(AppFont.eyebrow)
                        .textCase(.uppercase)
                        .foregroundStyle(AppColor.accentLight)
                        .padding(.bottom, Spacing.xs)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider().overlay(AppColor.glassBorder)
                        }
                        ShoppingRow(
                            name: item.displayName(locale: locale),
                            grams: RecipeLibraryEngine.displayGrams(item.grams),
                            isAtHome: item.isAtHome,
                            isBought: bought.contains(item.pantryKey),
                            toggle: { item.isAtHome ? toggleAtHome(item) : toggleBought(item) }
                        )
                        .contextMenu {
                            Button {
                                toggleAtHome(item)
                            } label: {
                                if item.isAtHome {
                                    Label("Not at home", systemImage: "house.slash")
                                } else {
                                    Label("I have this at home", systemImage: "house")
                                }
                            }
                        }
                    }
                }
            }
            Text("Hold an item to mark it as at home.")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textTertiary)
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }
}

private struct ShoppingRow: View {
    let name: String
    let grams: Int
    let isAtHome: Bool
    let isBought: Bool
    let toggle: () -> Void

    private var isDone: Bool { isAtHome || isBought }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Spacing.md) {
                Image(systemName: isAtHome ? "house.fill" : (isBought ? "checkmark.circle.fill" : "circle"))
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(isDone ? AppColor.positive : AppColor.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(name)
                    .strikethrough(isBought, color: AppColor.textTertiary)
                    .font(AppFont.body)
                    .foregroundStyle(isDone ? AppColor.textSecondary : AppColor.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Spacing.sm)
                if isAtHome {
                    Text("At home")
                        .font(AppFont.caption2.weight(.semibold))
                        .foregroundStyle(AppColor.positive)
                } else {
                    Text("\(grams) g")
                        .font(AppFont.subheadline)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .padding(.vertical, Spacing.sm)
            .frame(minHeight: Spacing.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(name), \(grams) g"))
        .accessibilityValue(isAtHome ? Text("At home") : (isBought ? Text("Bought") : Text("To buy")))
        .accessibilityAddTraits(isDone ? .isSelected : [])
    }
}

// MARK: - Prep day

/// The prep-day checklist: slow things started first, then the rest of
/// each recipe, then packing and cooling. Ends with putting the boxes away.
struct PrepDayCard: View {
    let tasks: [WeeklyPrepEngine.PrepTask]
    let recipes: [String: LibraryRecipe]
    let done: Set<String>
    let showsDish: Bool
    let toggle: (WeeklyPrepEngine.PrepTask) -> Void
    let finish: () -> Void

    @Environment(\.locale) private var locale

    private var doneCount: Int { tasks.filter { done.contains($0.id) }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            CardTitle(
                title: "Prep day",
                subtitle: Text("\(doneCount) of \(tasks.count) done"),
                isDone: doneCount == tasks.count
            )
            GlassProgressBar(progress: Double(doneCount) / Double(max(1, tasks.count)), gradient: nil)
                .accessibilityHidden(true)
            ForEach(WeeklyPrepEngine.PrepTask.Phase.allCases, id: \.self) { phase in
                let inPhase = tasks.filter { $0.phase == phase }
                if !inPhase.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title(for: phase))
                            .font(AppFont.eyebrow)
                            .textCase(.uppercase)
                            .foregroundStyle(AppColor.accentLight)
                            .padding(.bottom, Spacing.xs)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(inPhase) { task in
                            PrepTaskRow(
                                text: text(for: task),
                                dish: showsDish ? task.recipeID.flatMap { recipes[$0]?.displayName(locale: locale) } : nil,
                                isDone: done.contains(task.id),
                                toggle: { toggle(task) }
                            )
                        }
                    }
                }
            }
            PrimaryCTAButton(title: "Done — boxes in the fridge", icon: "shippingbox.fill", shape: .rounded, action: finish)
                .padding(.top, Spacing.xs)
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    private func title(for phase: WeeklyPrepEngine.PrepTask.Phase) -> LocalizedStringKey {
        switch phase {
        case .start: "Start first"
        case .cook:  "Cook"
        case .pack:  "Pack"
        }
    }

    private func text(for task: WeeklyPrepEngine.PrepTask) -> String {
        switch task.kind {
        case .step(let index):
            let steps = task.recipeID.flatMap { recipes[$0]?.displaySteps(locale: locale) } ?? []
            return steps.indices.contains(index) ? steps[index] : ""
        case .portion(let boxes):
            return String(localized: "Divide into \(boxes) boxes", comment: "Prep-day task: portion a dish into boxes")
        case .cool:
            return String(localized: "Let it cool, put the lids on and into the fridge", comment: "Last prep-day task")
        }
    }
}

private struct PrepTaskRow: View {
    let text: String
    let dish: String?
    let isDone: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(isDone ? AppColor.positive : AppColor.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(text)
                        .font(AppFont.body)
                        .foregroundStyle(isDone ? AppColor.textSecondary : AppColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let dish {
                        Text(dish)
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Spacing.sm)
            .frame(minHeight: Spacing.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isDone ? .isSelected : [])
    }
}

// MARK: - Boxes

/// The boxes in the fridge and freezer, soonest eat-by first.
struct PrepBoxesCard: View {
    let boxes: [PrepBoxBatch]
    let recipes: [String: LibraryRecipe]
    let now: Date
    let eat: (PrepBoxBatch) -> Void
    let freeze: (PrepBoxBatch) -> Void
    let discard: (PrepBoxBatch) -> Void

    private var total: Int { boxes.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            CardTitle(title: "Boxes in the fridge", subtitle: Text("\(total) boxes"), isDone: false)
            ForEach(Array(boxes.enumerated()), id: \.element.id) { index, batch in
                if index > 0 {
                    Divider().overlay(AppColor.glassBorder)
                }
                if let recipe = recipes[batch.recipeID] {
                    PrepBoxRow(
                        batch: batch,
                        recipe: recipe,
                        now: now,
                        eat: { eat(batch) },
                        freeze: { freeze(batch) },
                        discard: { discard(batch) }
                    )
                    .transition(.opacity)
                }
            }
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }
}

private struct PrepBoxRow: View {
    let batch: PrepBoxBatch
    let recipe: LibraryRecipe
    let now: Date
    let eat: () -> Void
    let freeze: () -> Void
    let discard: () -> Void

    @Environment(\.locale) private var locale

    private var calendar: Calendar { .current }

    private var eatBy: Date {
        WeeklyPrepEngine.eatBy(batch, fridgeDays: recipe.fridgeDays, calendar: calendar)
    }

    private var freshness: WeeklyPrepEngine.Freshness {
        WeeklyPrepEngine.freshness(eatBy: eatBy, now: now, calendar: calendar)
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            RecipeCutout(recipe: recipe)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(recipe.displayName(locale: locale))
                    .font(AppFont.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                Label { status } icon: {
                    Image(systemName: batch.isFrozen ? "snowflake" : "clock")
                }
                .font(AppFont.caption2.weight(.semibold))
                .foregroundStyle(statusColor)
                .labelStyle(.titleAndIcon)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Spacing.xs)
            Text("×\(batch.count)")
                .font(AppFont.headline)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(AppColor.textPrimary)
                .accessibilityLabel(Text("\(batch.count) boxes"))
            actions
        }
        .padding(.vertical, Spacing.sm)
    }

    @ViewBuilder
    private var actions: some View {
        if freshness == .expired {
            Button(action: discard) {
                Label("Throw out", systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.destructive)
                    .frame(width: 36, height: 36)
                    .glassControl(.circle)
                    .minimumHitArea()
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.9))
            .accessibilityLabel(Text("Throw out one box"))
        } else {
            Menu {
                Button(action: eat) {
                    Label("Eat a box", systemImage: "fork.knife")
                }
                if !batch.isFrozen {
                    Button(action: freeze) {
                        Label("Move one to the freezer", systemImage: "snowflake")
                    }
                }
                Button(role: .destructive, action: discard) {
                    Label("Throw out one box", systemImage: "trash")
                }
            } label: {
                Label("Eat a box", systemImage: "fork.knife")
                    .font(AppFont.chipText)
                    .foregroundStyle(AppColor.accentLight)
                    .padding(.horizontal, Spacing.md)
                    .frame(minHeight: 36)
                    .glassControl(.capsule)
                    .minimumHitArea()
            } primaryAction: {
                eat()
            }
            .accessibilityHint(Text("Logs one serving. Hold for more."))
        }
    }

    private var status: Text {
        switch freshness {
        case .expired:
            return Text("Past its eat-by day")
        case .soon:
            return calendar.isDate(eatBy, inSameDayAs: now) ? Text("Eat today") : Text("Eat by tomorrow")
        case .fresh where batch.isFrozen:
            return Text("Frozen · keeps until \(eatBy.formatted(.dateTime.day().month(.abbreviated).locale(locale)))")
        case .fresh:
            return Text("Eat by \(eatBy.formatted(.dateTime.weekday(.wide).locale(locale)))")
        }
    }

    private var statusColor: Color {
        switch freshness {
        case .expired: AppColor.destructive
        case .soon:    AppColor.warning
        case .fresh:   batch.isFrozen ? AppColor.belowRange : AppColor.textSecondary
        }
    }
}

// MARK: - Shared

/// A card's title with its one-line status under it.
private struct CardTitle: View {
    let title: LocalizedStringKey
    let subtitle: Text
    let isDone: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(AppFont.title3)
                .foregroundStyle(AppColor.textPrimary)
            subtitle
                .font(AppFont.subheadline)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(isDone ? AppColor.positive : AppColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Picker

/// Every meal-prep dish, best for this week first.
struct PrepDishPicker: View {
    let recipes: [LibraryRecipe]
    let planned: Set<String>
    let choose: (LibraryRecipe) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(recipes) { recipe in
                        let isPlanned = planned.contains(recipe.id)
                        Button {
                            choose(recipe)
                        } label: {
                            HStack(spacing: Spacing.md) {
                                RecipeCutout(recipe: recipe)
                                    .frame(width: 56, height: 56)
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(recipe.displayName(locale: locale))
                                        .font(AppFont.subheadline.weight(.semibold))
                                        .foregroundStyle(AppColor.textPrimary)
                                        .multilineTextAlignment(.leading)
                                    RecipeMetaLine(recipe: recipe)
                                }
                                Spacer(minLength: Spacing.sm)
                                if isPlanned {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(AppFont.scaled(20, weight: .semibold))
                                        .foregroundStyle(AppColor.positive)
                                        .accessibilityHidden(true)
                                }
                            }
                            .padding(Spacing.md)
                            .glassSurface(cornerRadius: Spacing.cardCornerRadius)
                        }
                        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
                        .disabled(isPlanned)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(isPlanned ? .isSelected : [])
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xl)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("Choose a dish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
