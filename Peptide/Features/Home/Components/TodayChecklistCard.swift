import SwiftUI

/// Today's "is the day logged?" card: meals, training, water, weight.
/// Every open row is also its own shortcut — tap meals to scan, training
/// to start, water to add a glass, weight to type today's number — so the
/// card answers "what's left" and closes the gap in the same place.
/// Without `onAction` it's a read-only record of a past day.
struct TodayChecklistCard: View {
    let state: TodayChecklistEngine.State
    let unit: MeasurementUnit
    /// Nil makes the rows display-only.
    var onAction: ((TodayChecklistEngine.Item) -> Void)?
    /// Names a browsed past day in the eyebrow. Nil means today.
    var dayTitle: String?

    private var isReadOnly: Bool { onAction == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HomeSectionHeader(eyebrow: dayTitle.map { LocalizedStringKey($0) } ?? "Today", title: "Daily checklist") {
                Text("\(state.completedCount)/\(TodayChecklistEngine.Item.allCases.count)")
                    .font(AppFont.scaled(16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(allDone ? AppColor.accentPrimary : AppColor.textSecondary)
                    .accessibilityLabel("\(state.completedCount) of \(TodayChecklistEngine.Item.allCases.count) done")
            }

            GlassCard {
                VStack(spacing: 0) {
                    ForEach(Array(TodayChecklistEngine.Item.allCases.enumerated()), id: \.element) { index, item in
                        if index > 0 {
                            Divider()
                                .overlay(AppColor.glassBorder)
                                .padding(.leading, Spacing.minimumHitTarget + Spacing.md)
                        }
                        row(item)
                    }
                }
            }
        }
        .appAnimation(AppAnimation.springSmooth, value: state)
    }

    private var allDone: Bool {
        state.completedCount == TodayChecklistEngine.Item.allCases.count
    }

    @ViewBuilder
    private func row(_ item: TodayChecklistEngine.Item) -> some View {
        let done = state.isDone(item)
        if let onAction {
            Button {
                Haptics.impact(.light)
                onAction(item)
            } label: {
                rowContent(item, done: done)
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.98))
            .accessibilityElement(children: .combine)
            .accessibilityValue(done ? Text("Done") : Text("Not done"))
            .accessibilityHint(hint(item))
        } else {
            rowContent(item, done: done)
                .accessibilityElement(children: .combine)
                .accessibilityValue(done ? Text("Done") : Text("Not done"))
        }
    }

    private func rowContent(_ item: TodayChecklistEngine.Item, done: Bool) -> some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(done ? AppColor.accentFill : AppColor.surfaceSecondary.opacity(0.6))
                Image(systemName: done ? "checkmark" : icon(item))
                    .font(AppFont.scaled(13, weight: .bold))
                    .foregroundStyle(done ? AppColor.onAccent : AppColor.textSecondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: Spacing.minimumHitTarget, height: Spacing.minimumHitTarget)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title(item))
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                Text(detail(item))
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: Spacing.sm)

            if !isReadOnly {
                trailing(item, done: done)
            }
        }
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func trailing(_ item: TodayChecklistEngine.Item, done: Bool) -> some View {
        switch item {
        case .water:
            Text("+\(unit == .metric ? "250 mL" : "8 oz")")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.accentPrimary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .glassControl(.capsule, tint: AppColor.accentPrimary.opacity(0.15), interactive: false)
        default:
            if !done {
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
    }

    private func icon(_ item: TodayChecklistEngine.Item) -> String {
        switch item {
        case .meals:    "fork.knife"
        case .training: "dumbbell.fill"
        case .water:    "drop.fill"
        case .weight:   "scalemass.fill"
        }
    }

    private func title(_ item: TodayChecklistEngine.Item) -> LocalizedStringKey {
        switch item {
        case .meals:    "Meals"
        case .training: state.isTrainingDay ? "Training" : "Rest day"
        case .water:    "Water"
        case .weight:   "Weigh-in"
        }
    }

    private func detail(_ item: TodayChecklistEngine.Item) -> String {
        switch item {
        case .meals:
            if state.isDone(.meals) {
                return String(localized: "Breakfast, lunch and dinner logged")
            }
            if isReadOnly { return String(localized: "\(state.loggedMainMealCount) of 3 logged") }
            guard let next = state.nextMeal else {
                return String(localized: "\(state.loggedMainMealCount) of 3 logged")
            }
            return String(localized: "\(state.loggedMainMealCount) of 3 logged · \(next.displayName) next")
        case .training:
            if state.trainedToday { return String(localized: "Workout logged") }
            if isReadOnly, state.isTrainingDay { return String(localized: "No workout logged") }
            return state.isTrainingDay
                ? String(localized: "On the plan today — tap to start")
                : String(localized: "Recovery counts too")
        case .water:
            let target = Double(TodayChecklistEngine.waterTargetOz)
            return String(localized: "\(unit.volumeLabel(state.waterFluidOunces)) of \(unit.volumeLabel(target))")
        case .weight:
            guard let kg = state.weightTodayKg else {
                return isReadOnly ? String(localized: "No weigh-in logged") : String(localized: "Tap to log today's weight")
            }
            return unit.weightLabel(kg, fractionDigits: 1)
        }
    }

    private func hint(_ item: TodayChecklistEngine.Item) -> Text {
        switch item {
        case .meals:    Text("Opens the meal scanner")
        case .training: Text("Opens Train")
        case .water:    Text("Adds a glass of water")
        case .weight:   Text("Opens weight entry")
        }
    }
}

/// Type today's weight in the user's unit. Accepts "82,4" and "82.4"
/// alike and refuses implausible values instead of saving them.
struct LogWeightSheet: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var unit: MeasurementUnit { dataStore.profile.bodyMetrics.unit }

    private var parsedKg: Double? {
        DailyReminderEngine.parsedWeightKilograms(text, unit: unit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Today's weight")
                    .font(AppFont.title2)
                    .foregroundStyle(AppColor.textPrimary)
                if let last = dataStore.dedupedWeightHistory.last {
                    Text("Last: \(unit.weightLabel(last.kg, fractionDigits: 1))")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textTertiary)
                }
            }

            GlassTextField(placeholder: "Weight in \(unit.weightSuffix)", text: $text, icon: "scalemass.fill")
                .keyboardType(.decimalPad)

            GlassButton(title: "Save", icon: "checkmark", isFullWidth: true) {
                guard let kg = parsedKg else { return }
                dataStore.logWeight(kg: kg)
                Haptics.success()
                dismiss()
            }
            .disabled(parsedKg == nil)
        }
        .padding(Spacing.screenPadding)
        .presentationDetents([.medium])
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        TodayChecklistCard(
            state: .init(
                loggedMeals: [.breakfast],
                trainedToday: false,
                isTrainingDay: true,
                waterFluidOunces: 40,
                weightTodayKg: 82.4,
                currentMeal: .lunch
            ),
            unit: .metric,
            onAction: { _ in }
        )
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
