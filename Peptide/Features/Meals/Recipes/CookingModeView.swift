import SwiftUI

/// Full-screen cooking: one step at a time in big type, what it needs right
/// under it, its timers as cards with one clear Start, a peek at the next
/// step, and Next to tick it off. Swipe works too. The screen stays awake while it's open, so floury hands
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
                    CookingStepPage(step: step, next: steps.first { $0.id == step.id + 1 }, timers: timers)
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

    /// One segment per step: the one you're on in full accent, ticked ones
    /// in a softer accent, the rest as track.
    private var progress: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(steps) { step in
                Capsule(style: .continuous)
                    .fill(segmentFill(for: step.id))
                    .frame(height: 6)
            }
        }
        .appAnimation(AppAnimation.springSnappy, value: done)
        .appAnimation(AppAnimation.springSnappy, value: index)
        .accessibilityHidden(true)
    }

    private func segmentFill(for id: Int) -> Color {
        if id == index { return AppColor.accentPrimary }
        return done.contains(id) ? AppColor.accentPrimary.opacity(0.4) : AppColor.track
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
                                Text(verbatim: "·")
                                    .accessibilityHidden(true)
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
            // Hidden, not dimmed, on the first step: a faint button reads as
            // broken. It keeps its place so Next doesn't jump.
            .opacity(index == 0 ? 0 : 1)
            .accessibilityHidden(index == 0)
            GlassButton(
                title: isLast ? "Finish cooking" : "Next step",
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

/// One step's page: the instruction large enough to read from the stove,
/// then what to gather, then what to wait for, then what comes next.
private struct CookingStepPage: View {
    let step: RecipeStepEngine.Step
    let next: RecipeStepEngine.Step?
    let timers: CookingTimers

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                Text(step.text)
                    .font(AppFont.scaled(28, weight: .regular, relativeTo: .title1))
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !step.ingredients.isEmpty {
                    ingredients
                }
                ForEach(Array(step.timers.enumerated()), id: \.offset) { index, timer in
                    StepTimerCard(
                        key: CookingTimers.Key(step: step.id, index: index),
                        seconds: timer.seconds,
                        timers: timers
                    )
                }
                if let next {
                    upNext(next)
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
            sectionLabel("You need")
            VStack(spacing: 0) {
                ForEach(Array(step.ingredients.enumerated()), id: \.offset) { position, ingredient in
                    if position > 0 {
                        Divider().overlay(AppColor.glassBorder)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(ingredient.name)
                            .font(AppFont.title3.weight(.regular))
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer(minLength: Spacing.sm)
                        Text("\(ingredient.grams) g")
                            .font(AppFont.title3.weight(.regular))
                            .monospacedDigit()
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .padding(.vertical, Spacing.md)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, Spacing.cardPadding)
            .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        }
    }

    private func upNext(_ next: RecipeStepEngine.Step) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionLabel("Next up")
            Text(next.text)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textTertiary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    private func sectionLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(AppFont.eyebrow)
            .textCase(.uppercase)
            .foregroundStyle(AppColor.textSecondary)
    }
}

/// A timed wait as a card you can't miss from the stove: the time large,
/// one Start button, the live countdown and Stop while it runs, a check
/// once it has rung.
private struct StepTimerCard: View {
    let key: CookingTimers.Key
    let seconds: Int
    let timers: CookingTimers

    private var isRunning: Bool { timers.isRunning(key) }
    private var hasRung: Bool { timers.finished.contains(key) }
    private var tint: Color { hasRung ? AppColor.success : AppColor.accentInkOnWash }

    /// Ticks every second while the timer runs, so the countdown and its
    /// VoiceOver value stay live; idle, it barely ticks at all.
    var body: some View {
        TimelineView(.periodic(from: .now, by: isRunning ? 1 : 3600)) { context in
            card(now: context.date)
        }
    }

    private func card(now: Date) -> some View {
        Button(action: tap) {
            HStack(spacing: Spacing.md) {
                Image(systemName: hasRung ? "checkmark" : "timer")
                    .font(AppFont.title3)
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Spacing.minimumHitTarget, height: Spacing.minimumHitTarget)
                    .background(tint.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    (hasRung ? Text("Done") : Text("Timer"))
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                    time(now: now)
                        .font(AppFont.scaled(28, weight: .regular, relativeTo: .title1))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                }
                Spacer(minLength: Spacing.sm)
                (isRunning ? Text("Stop") : Text("Start"))
                    .font(AppFont.subheadline.weight(.semibold))
                    .foregroundStyle(isRunning ? AppColor.textPrimary : AppColor.onAccent)
                    .padding(.horizontal, Spacing.lg)
                    .frame(minHeight: Spacing.minimumHitTarget)
                    .background(isRunning ? AppColor.track : AppColor.accentFill, in: Capsule(style: .continuous))
            }
            .padding(Spacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: Spacing.cardCornerRadius)
            .contentShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .appAnimation(AppAnimation.springSnappy, value: isRunning)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasRung ? Text("Timer done") : Text("Timer, \(CookingTimers.label(seconds: seconds))"))
        .accessibilityValue(remainingValue(now: now))
        .accessibilityHint(isRunning ? Text("Stops the timer") : Text("Starts the timer"))
        .accessibilityAddTraits(.isButton)
    }

    private func time(now: Date) -> Text {
        if let end = timers.endDates[key] {
            return Text(CookingTimers.clock(end.timeIntervalSince(now)))
        }
        return Text(CookingTimers.label(seconds: seconds))
    }

    /// The live countdown, which the fixed label can't carry.
    private func remainingValue(now: Date) -> Text {
        guard let end = timers.endDates[key] else { return Text(verbatim: "") }
        let remaining = max(0, Int(end.timeIntervalSince(now).rounded(.up)))
        return Text("\(CookingTimers.label(seconds: remaining)) left")
    }

    private func tap() {
        if isRunning {
            timers.cancel(key)
        } else {
            timers.start(key, seconds: seconds)
        }
        Haptics.selection()
    }
}
