import SwiftUI

/// Full-screen cooking: one step at a time in big type, what it needs right
/// under it, its timers as large buttons, and Next to tick it off. Swipe
/// works too. The screen stays awake while it's open, so floury hands
/// never have to unlock the phone.
struct CookingModeView: View {
    let recipeName: String
    let steps: [RecipeStepEngine.Step]
    @Binding var done: Set<Int>
    let timers: CookingTimers

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int

    init(recipeName: String, steps: [RecipeStepEngine.Step], done: Binding<Set<Int>>, timers: CookingTimers) {
        self.recipeName = recipeName
        self.steps = steps
        _done = done
        self.timers = timers
        // Picks up where the checklist left off.
        let firstOpen = steps.first { !done.wrappedValue.contains($0.id) }?.id ?? 0
        _index = State(initialValue: firstOpen)
    }

    private var isLast: Bool { index >= steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            progress
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
            otherTimers
            TabView(selection: $index) {
                ForEach(steps) { step in
                    CookingStepPage(step: step, timers: timers)
                        .tag(step.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            bottomBar
        }
        .background(AppColor.background.ignoresSafeArea())
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: Spacing.md) {
            GlassIconButton(icon: "xmark", accessibilityLabel: "Close cooking mode") { dismiss() }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(recipeName)
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
                Text("Step \(index + 1) of \(steps.count)")
                    .font(AppFont.headline)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(AppColor.textPrimary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.sm)
    }

    /// One segment per step: ticked steps solid, the open one outlined.
    private var progress: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(steps) { step in
                Capsule(style: .continuous)
                    .fill(segmentFill(for: step.id))
                    .frame(height: 4)
            }
        }
        .appAnimation(AppAnimation.springSnappy, value: done)
        .appAnimation(AppAnimation.springSnappy, value: index)
        .accessibilityHidden(true)
    }

    private func segmentFill(for id: Int) -> Color {
        if done.contains(id) { return AppColor.positive }
        return id == index ? AppColor.accentPrimary : AppColor.track
    }

    /// Timers started on other steps stay in sight, so the pasta doesn't
    /// boil over while you're two steps on.
    @ViewBuilder
    private var otherTimers: some View {
        let elsewhere = timers.running.filter { $0.key.step != index }
        if !elsewhere.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(elsewhere) { entry in
                        Button {
                            AppAnimation.with(AppAnimation.springSnappy) { index = entry.key.step }
                        } label: {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "timer")
                                    .accessibilityHidden(true)
                                Text("Step \(entry.key.step + 1)")
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    Text(CookingTimers.clock(entry.end.timeIntervalSince(context.date)))
                                        .monospacedDigit()
                                }
                            }
                            .font(AppFont.footnote.weight(.semibold))
                            .foregroundStyle(AppColor.accentInkOnWash)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.xs)
                            .background(AppColor.accentPrimary.opacity(0.18), in: Capsule(style: .continuous))
                            .minimumHitArea()
                        }
                        .buttonStyle(ScalePressStyle(pressedScale: 0.94))
                        .accessibilityHint(Text("Goes to that step"))
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
            }
            .padding(.top, Spacing.md)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: Spacing.md) {
            GlassIconButton(icon: "chevron.left", accessibilityLabel: "Previous step") {
                AppAnimation.with(AppAnimation.springSnappy) { index = max(0, index - 1) }
                Haptics.selection()
            }
            .disabled(index == 0)
            .opacity(index == 0 ? 0.4 : 1)
            GlassButton(
                title: isLast ? "Finish cooking" : "Next step",
                icon: isLast ? "checkmark" : "arrow.right",
                style: .primary,
                isFullWidth: true,
                action: advance
            )
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm)
    }

    /// Ticks the step off and moves on; the last one closes cooking mode
    /// back onto the recipe, where logging the serving is one tap.
    private func advance() {
        guard steps.indices.contains(index) else { return dismiss() }
        // Read before the index moves: `isLast` follows `index`.
        let wasLast = isLast
        AppAnimation.with(AppAnimation.springSnappy) {
            _ = done.insert(steps[index].id)
            if !wasLast { index += 1 }
        }
        if wasLast {
            Haptics.success()
            dismiss()
        } else {
            Haptics.impact(.light)
        }
    }
}

/// One step's page: the instruction large enough to read from the stove.
private struct CookingStepPage: View {
    let step: RecipeStepEngine.Step
    let timers: CookingTimers

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Text(step.text)
                    .font(AppFont.scaled(28, weight: .regular, relativeTo: .title1))
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !step.timers.isEmpty {
                    FlowLayout(spacing: Spacing.sm) {
                        ForEach(Array(step.timers.enumerated()), id: \.offset) { index, timer in
                            StepTimerChip(
                                key: CookingTimers.Key(step: step.id, index: index),
                                seconds: timer.seconds,
                                timers: timers,
                                isLarge: true
                            )
                        }
                    }
                }
                if !step.ingredients.isEmpty {
                    ingredients
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableContentWidth()
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("You need")
                .font(AppFont.eyebrow)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.textSecondary)
            VStack(spacing: 0) {
                ForEach(Array(step.ingredients.enumerated()), id: \.offset) { position, ingredient in
                    if position > 0 {
                        Divider().overlay(AppColor.glassBorder)
                    }
                    HStack {
                        Text(ingredient.name)
                            .font(AppFont.title3.weight(.regular))
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer(minLength: Spacing.sm)
                        Text("\(ingredient.grams) g")
                            .font(AppFont.title3)
                            .monospacedDigit()
                            .foregroundStyle(AppColor.textPrimary)
                    }
                    .padding(.vertical, Spacing.md)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, Spacing.cardPadding)
            .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        }
    }
}
