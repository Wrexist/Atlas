import SwiftUI

/// "Method" as a checklist: each step is a task you tick off, with the
/// ingredients it uses (scaled to the servings being cooked) and any timed
/// wait as a one-tap timer underneath. The first unticked step is lifted
/// onto a well so you find your place again after looking away.
struct RecipeMethodCard: View {
    let steps: [RecipeStepEngine.Step]
    @Binding var done: Set<Int>
    let timers: CookingTimers
    let startCooking: () -> Void

    private var currentStep: Int? {
        steps.first { !done.contains($0.id) }?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header
            VStack(spacing: Spacing.xs) {
                ForEach(steps) { step in
                    RecipeStepRow(
                        step: step,
                        isDone: done.contains(step.id),
                        isCurrent: step.id == currentStep,
                        timers: timers,
                        toggle: { toggle(step.id) }
                    )
                }
            }
            GlassButton(title: "Cook step by step", icon: "frying.pan.fill", style: .primary, isFullWidth: true, action: startCooking)
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Method")
                .font(AppFont.title3)
                .foregroundStyle(AppColor.textPrimary)
            Spacer(minLength: Spacing.sm)
            Text("\(done.count) of \(steps.count) done")
                .font(AppFont.subheadline)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(done.count == steps.count ? AppColor.positive : AppColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func toggle(_ id: Int) {
        AppAnimation.with(AppAnimation.springSnappy) {
            if done.contains(id) { done.remove(id) } else { done.insert(id) }
        }
        Haptics.impact(.light)
    }
}

/// One step: a numbered check, the instruction, then what it needs.
private struct RecipeStepRow: View {
    let step: RecipeStepEngine.Step
    let isDone: Bool
    let isCurrent: Bool
    let timers: CookingTimers
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Button(action: toggle) {
                StepCheck(number: step.id + 1, isDone: isDone)
                    .minimumHitArea()
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.9))
            .accessibilityLabel(Text("Step \(step.id + 1): \(step.text)"))
            .accessibilityValue(isDone ? Text("Done") : Text("Not done"))
            .accessibilityAddTraits(isDone ? .isSelected : [])
            .accessibilityHint(Text("Marks the step as done"))

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(step.text)
                    .font(AppFont.body)
                    .foregroundStyle(isDone ? AppColor.textTertiary : AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: toggle)
                    .accessibilityHidden(true)
                if !isDone, !step.ingredients.isEmpty || !step.timers.isEmpty {
                    FlowLayout(spacing: Spacing.xs) {
                        ForEach(step.ingredients, id: \.self) { StepIngredientChip(ingredient: $0) }
                        ForEach(Array(step.timers.enumerated()), id: \.offset) { index, timer in
                            StepTimerChip(
                                key: CookingTimers.Key(step: step.id, index: index),
                                seconds: timer.seconds,
                                timers: timers
                            )
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.concentric(in: Spacing.cardCornerRadius, inset: Spacing.cardPadding), style: .continuous)
                .fill(isCurrent ? AppColor.surfaceSecondary : Color.clear)
        }
        .accessibilityElement(children: .contain)
    }
}

/// The step number in an accent wash; a filled check once it's done.
struct StepCheck: View {
    let number: Int
    let isDone: Bool
    var diameter: CGFloat = 28

    var body: some View {
        ZStack {
            Circle()
                .fill(isDone ? AppColor.positive : AppColor.accentPrimary.opacity(0.18))
            if isDone {
                Image(systemName: "checkmark")
                    .font(AppFont.scaled(diameter * 0.45, weight: .bold, relativeTo: .caption1))
                    .foregroundStyle(AppColor.onAccent)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else {
                Text("\(number)")
                    .font(AppFont.scaled(diameter * 0.48, weight: .semibold, relativeTo: .caption1))
                    .monospacedDigit()
                    .foregroundStyle(AppColor.accentInkOnWash)
                    .transition(.opacity)
            }
        }
        // Grows with the digit inside it, so "12" never spills out at large
        // text sizes.
        .frame(width: AppFont.scaledValue(diameter, relativeTo: .caption1),
               height: AppFont.scaledValue(diameter, relativeTo: .caption1))
        .appAnimation(AppAnimation.springSnappy, value: isDone)
        .accessibilityHidden(true)
    }
}

/// "Nötfärs · 125 g": what the step takes, so the cook never scrolls back
/// up to the list mid-step.
struct StepIngredientChip: View {
    let ingredient: RecipeStepEngine.StepIngredient

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(ingredient.name)
                .foregroundStyle(AppColor.textPrimary)
            Text("\(ingredient.grams) g")
                .monospacedDigit()
                .foregroundStyle(AppColor.textSecondary)
        }
        .font(AppFont.footnote)
        .lineLimit(1)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(AppColor.surfaceSecondary, in: Capsule(style: .continuous))
        .overlay { Capsule(style: .continuous).strokeBorder(AppColor.glassBorder, lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// A timed wait as a button: tap to start, the live countdown while it
/// runs, a check when it has rung. Tapping a running timer stops it.
struct StepTimerChip: View {
    let key: CookingTimers.Key
    let seconds: Int
    let timers: CookingTimers
    var isLarge = false

    private var isRunning: Bool { timers.isRunning(key) }
    private var hasRung: Bool { timers.finished.contains(key) }

    var body: some View {
        Button(action: tap) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: hasRung ? "checkmark.circle.fill" : (isRunning ? "stop.circle.fill" : "timer"))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                label
            }
            .font(isLarge ? AppFont.headline : AppFont.footnote.weight(.semibold))
            .foregroundStyle(hasRung ? AppColor.positive : AppColor.accentInkOnWash)
            .padding(.horizontal, isLarge ? Spacing.lg : Spacing.sm)
            .padding(.vertical, isLarge ? Spacing.md : Spacing.xs)
            .background(AppColor.accentPrimary.opacity(isRunning ? 0.24 : 0.14), in: Capsule(style: .continuous))
            .minimumHitArea()
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.94))
        .appAnimation(AppAnimation.springSnappy, value: isRunning)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isRunning ? Text("Stops the timer") : Text("Starts the timer"))
    }

    @ViewBuilder
    private var label: some View {
        if let end = timers.endDates[key] {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(CookingTimers.clock(end.timeIntervalSince(context.date)))
                    .monospacedDigit()
            }
        } else if hasRung {
            Text("Done")
        } else {
            Text(CookingTimers.label(seconds: seconds))
                .monospacedDigit()
        }
    }

    private var accessibilityLabel: Text {
        hasRung ? Text("Timer done") : Text("Timer, \(CookingTimers.label(seconds: seconds))")
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
