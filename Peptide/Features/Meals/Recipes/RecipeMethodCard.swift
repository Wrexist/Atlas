import SwiftUI

/// "Method" as a checklist on a timeline: each step is a task you tick off,
/// with the ingredients it uses (scaled to the servings being cooked) as a
/// quiet line under it and any timed wait as its own button below that.
/// The first unticked step is the only one in full ink with a filled
/// number, so you find your place again after looking away.
struct RecipeMethodCard: View {
    let steps: [RecipeStepEngine.Step]
    @Binding var done: Set<Int>
    let timers: CookingTimers
    let startCooking: () -> Void

    private var currentStep: Int? {
        steps.first { !done.contains($0.id) }?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            header
            VStack(spacing: 0) {
                ForEach(steps) { step in
                    RecipeStepRow(
                        step: step,
                        state: state(of: step.id),
                        isLast: step.id == steps.last?.id,
                        timers: timers,
                        toggle: { toggle(step.id) }
                    )
                }
            }
            GlassButton(title: "Cook step by step", icon: "frying.pan.fill", style: .secondary, isFullWidth: true, action: startCooking)
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    private func state(of id: Int) -> StepCheck.State {
        if done.contains(id) { return .done }
        return id == currentStep ? .current : .upcoming
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Method")
                    .font(AppFont.title3)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: Spacing.sm)
                Text("\(done.count) of \(steps.count) done")
                    .font(AppFont.subheadline)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(isFinished ? AppColor.positive : AppColor.textSecondary)
            }
            ProgressView(value: Double(done.count), total: Double(max(steps.count, 1)))
                .progressViewStyle(.linear)
                .tint(isFinished ? AppColor.positive : AppColor.accentPrimary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private var isFinished: Bool { !steps.isEmpty && done.count == steps.count }

    private func toggle(_ id: Int) {
        AppAnimation.with(AppAnimation.springSnappy) {
            if done.contains(id) { done.remove(id) } else { done.insert(id) }
        }
        Haptics.impact(.light)
    }
}

/// One step: the number on a rail that joins it to the next, the
/// instruction, then what it needs and how long it waits.
private struct RecipeStepRow: View {
    let step: RecipeStepEngine.Step
    let state: StepCheck.State
    let isLast: Bool
    let timers: CookingTimers
    let toggle: () -> Void

    private var diameter: CGFloat { AppFont.scaledValue(StepCheck.defaultDiameter, relativeTo: .caption1) }
    /// The check's tap target, which the circle sits centred in.
    private var slot: CGFloat { max(Spacing.minimumHitTarget, diameter) }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Button(action: toggle) {
                StepCheck(number: step.id + 1, state: state)
                    .minimumHitArea()
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.9))
            .accessibilityLabel(Text("Step \(step.id + 1): \(step.text)"))
            .accessibilityValue(state == .done ? Text("Done") : Text("Not done"))
            .accessibilityAddTraits(state == .done ? .isSelected : [])
            .accessibilityHint(Text("Marks the step as done"))

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(step.text)
                    .font(state == .current ? AppFont.body.weight(.medium) : AppFont.body)
                    .foregroundStyle(textColor)
                    .lineLimit(state == .done ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: toggle)
                    .accessibilityHidden(true)
                if state != .done {
                    if !step.ingredients.isEmpty {
                        StepIngredientLine(ingredients: step.ingredients)
                    }
                    if !step.timers.isEmpty {
                        HStack(spacing: Spacing.sm) {
                            ForEach(Array(step.timers.enumerated()), id: \.offset) { index, timer in
                                StepTimerChip(
                                    key: CookingTimers.Key(step: step.id, index: index),
                                    seconds: timer.seconds,
                                    timers: timers
                                )
                            }
                        }
                        .padding(.top, Spacing.xxs)
                    }
                }
            }
            // Centres the first line of text on the number.
            .padding(.top, max(0, (slot - AppFont.scaledValue(22, relativeTo: .body)) / 2))
            .padding(.bottom, isLast ? 0 : Spacing.xl)
        }
        .background(alignment: .topLeading) {
            if !isLast {
                Capsule(style: .continuous)
                    .fill(state == .done ? AppColor.positive.opacity(0.5) : AppColor.track)
                    .frame(width: 2)
                    .padding(.top, (slot + diameter) / 2 + Spacing.xs)
                    .padding(.bottom, Spacing.xs - (slot - diameter) / 2)
                    .padding(.leading, slot / 2 - 1)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var textColor: Color {
        switch state {
        case .current: AppColor.textPrimary
        case .upcoming: AppColor.textSecondary
        case .done: AppColor.textTertiary
        }
    }
}

/// The step number: filled in the accent for the step you're on, an
/// outline for the ones ahead, a green check once it's done.
struct StepCheck: View {
    enum State { case current, upcoming, done }

    static let defaultDiameter: CGFloat = 28

    let number: Int
    let state: State
    var diameter: CGFloat = defaultDiameter

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
            if state == .upcoming {
                Circle()
                    .strokeBorder(AppColor.track, lineWidth: 1.5)
            }
            if state == .done {
                Image(systemName: "checkmark")
                    .font(AppFont.scaled(diameter * 0.45, weight: .bold, relativeTo: .caption1))
                    .foregroundStyle(AppColor.onAccent)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else {
                Text("\(number)")
                    .font(AppFont.scaled(diameter * 0.48, weight: .semibold, relativeTo: .caption1))
                    .monospacedDigit()
                    .foregroundStyle(state == .current ? AppColor.onAccent : AppColor.textSecondary)
                    .transition(.opacity)
            }
        }
        // Grows with the digit inside it, so "12" never spills out at large
        // text sizes.
        .frame(width: AppFont.scaledValue(diameter, relativeTo: .caption1),
               height: AppFont.scaledValue(diameter, relativeTo: .caption1))
        .appAnimation(AppAnimation.springSnappy, value: state)
        .accessibilityHidden(true)
    }

    private var fill: Color {
        switch state {
        case .current: AppColor.accentFill
        case .upcoming: Color.clear
        case .done: AppColor.positive
        }
    }
}

/// "Potatis 900 g · Ströbröd 30 g": what the step takes as one quiet
/// line, so it reads as a note on the step instead of a row of buttons
/// competing with the timer.
struct StepIngredientLine: View {
    let ingredients: [RecipeStepEngine.StepIngredient]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Image(systemName: "basket")
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textTertiary)
                .accessibilityHidden(true)
            ingredients.enumerated().reduce(Text(verbatim: "")) { line, entry in
                let (position, ingredient) = entry
                let separator = position == 0 ? Text(verbatim: "") : Text(verbatim: "  ·  ").foregroundStyle(AppColor.textTertiary)
                return line + separator
                    + Text(verbatim: ingredient.name).foregroundStyle(AppColor.textSecondary)
                    + Text(verbatim: " \(ingredient.grams) g").foregroundStyle(AppColor.textTertiary).monospacedDigit()
            }
            .font(AppFont.subheadline)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A timed wait as a button: tap to start, the live countdown while it
/// runs, a check when it has rung. Tapping a running timer stops it.
struct StepTimerChip: View {
    let key: CookingTimers.Key
    let seconds: Int
    let timers: CookingTimers

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
            .font(AppFont.subheadline.weight(.semibold))
            .foregroundStyle(hasRung ? AppColor.positive : AppColor.accentInkOnWash)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs + Spacing.xxs)
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
