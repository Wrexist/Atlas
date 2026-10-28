import SwiftUI

/// Today's "is the day logged?" card: meals, training, water, weight.
/// Every open row is also its own shortcut — tap meals to scan, training
/// to start, water to add a glass, weight to type today's number — so the
/// card answers "what's left" and closes the gap in the same place.
/// Daily supplements follow as one-tap checks and count toward the total.
/// Without `onAction` it's a read-only record of a past day.
struct TodayChecklistCard: View {
    let state: TodayChecklistEngine.State
    let unit: MeasurementUnit
    /// Nil makes the rows display-only.
    var onAction: ((TodayChecklistEngine.Item) -> Void)?
    /// Names a browsed past day in the eyebrow. Nil means today.
    var dayTitle: String?
    /// The day's supplements, one check each, below the logging rows.
    var supplements: [SupplementEngine.Row] = []
    /// Nil makes the supplement rows display-only.
    var onToggleSupplement: ((UUID) -> Void)?
    /// Opens the supplement list. Nil hides the way in (a past day).
    var onManageSupplements: (() -> Void)?

    private var isReadOnly: Bool { onAction == nil }

    private var totalCount: Int { TodayChecklistEngine.Item.allCases.count + supplements.count }

    private var completedCount: Int { state.completedCount + supplements.filter(\.isTaken).count }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HomeSectionHeader(eyebrow: dayTitle.map { LocalizedStringKey($0) } ?? "Today", title: "Daily checklist") {
                Text("\(completedCount)/\(totalCount)")
                    .font(AppFont.scaled(16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(allDone ? AppColor.accentPrimary : AppColor.textSecondary)
                    .accessibilityLabel("\(completedCount) of \(totalCount) done")
            }

            GlassCard {
                VStack(spacing: 0) {
                    ForEach(Array(TodayChecklistEngine.Item.allCases.enumerated()), id: \.element) { index, item in
                        if index > 0 { rowDivider }
                        row(item)
                    }
                    supplementsBlock
                    if allDone {
                        dayCompleteFooter
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .appAnimation(AppAnimation.springSmooth, value: state)
        .appAnimation(AppAnimation.springSnappy, value: supplements)
    }

    /// The end state of the day's loop — a finished checklist says so
    /// rather than only recolouring the counter.
    private var dayCompleteFooter: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(AppColor.accentPrimary)
                .accessibilityHidden(true)
            (isReadOnly ? Text("Every item was logged that day.") : Text("Day logged — every item is checked off."))
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.accentPrimary.opacity(0.12))
        }
        .padding(.top, Spacing.sm)
        .accessibilityElement(children: .combine)
    }

    /// Partial progress for the rows that fill up over the day, drawn
    /// as a ring around the row's icon so "1 of 3" reads at a glance.
    private func progress(_ item: TodayChecklistEngine.Item) -> Double {
        switch item {
        case .meals:
            Double(state.loggedMainMealCount) / Double(TodayChecklistEngine.mainMeals.count)
        case .water:
            state.waterProgress
        case .training, .weight:
            0
        }
    }

    private var allDone: Bool {
        completedCount == totalCount
    }

    // MARK: - Supplements

    /// The supplement rows under a quiet eyebrow, or — on today with none
    /// set up — one row that offers them.
    @ViewBuilder
    private var supplementsBlock: some View {
        if !supplements.isEmpty {
            rowDivider
            HStack {
                Text("Supplements")
                    .font(AppFont.eyebrow)
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.textTertiary)
                Spacer(minLength: Spacing.sm)
                if let onManageSupplements {
                    Button("Manage") {
                        Haptics.impact(.light)
                        onManageSupplements()
                    }
                    .font(AppFont.chipText)
                    .foregroundStyle(AppColor.accentLight)
                    .minimumHitArea()
                    .buttonStyle(ScalePressStyle())
                    .accessibilityHint("Opens your supplement list")
                }
            }
            .padding(.top, Spacing.sm)
            ForEach(Array(supplements.enumerated()), id: \.element.id) { index, row in
                if index > 0 { rowDivider }
                supplementRow(row)
            }
        } else if let onManageSupplements {
            rowDivider
            Button {
                Haptics.impact(.light)
                onManageSupplements()
            } label: {
                addSupplementsRow
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.98))
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens your supplement list")
        }
    }

    private var rowDivider: some View {
        Divider()
            .overlay(AppColor.glassBorder)
            .padding(.leading, Spacing.minimumHitTarget + Spacing.md)
    }

    private var addSupplementsRow: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "plus")
                .font(AppFont.scaled(13, weight: .bold))
                .foregroundStyle(AppColor.accentLight)
                .frame(width: Spacing.minimumHitTarget, height: Spacing.minimumHitTarget)
                .background(Circle().fill(AppColor.surfaceSecondary.opacity(0.6)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Supplements")
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                Text("Creatine, vitamin D, omega-3 — one check a day")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
            }
            Spacer(minLength: Spacing.sm)
            Image(systemName: "chevron.right")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func supplementRow(_ row: SupplementEngine.Row) -> some View {
        if let onToggleSupplement {
            Button {
                onToggleSupplement(row.id)
            } label: {
                supplementRowContent(row)
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.98))
            .accessibilityElement(children: .combine)
            .accessibilityValue(row.isTaken ? Text("Taken") : Text("Not taken"))
            .accessibilityHint(row.isTaken ? Text("Marks it as not taken") : Text("Marks it as taken today"))
        } else {
            supplementRowContent(row)
                .accessibilityElement(children: .combine)
                .accessibilityValue(row.isTaken ? Text("Taken") : Text("Not taken"))
        }
    }

    private func supplementRowContent(_ row: SupplementEngine.Row) -> some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(row.isTaken ? AppColor.accentFill : AppColor.surfaceSecondary.opacity(0.6))
                Image(systemName: row.isTaken ? "checkmark" : row.supplement.symbol)
                    .font(AppFont.scaled(13, weight: .bold))
                    .foregroundStyle(row.isTaken ? AppColor.onAccent : AppColor.textSecondary)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: row.isTaken)
            }
            .frame(width: Spacing.minimumHitTarget, height: Spacing.minimumHitTarget)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(row.supplement.name)
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                if !row.supplement.detailText.isEmpty {
                    Text(row.supplement.detailText)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textTertiary)
                }
            }

            Spacer(minLength: Spacing.sm)
        }
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
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
                if !done, progress(item) > 0 {
                    Circle()
                        .trim(from: 0, to: progress(item))
                        .stroke(AppColor.accentPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1.5)
                }
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
            Text("+\(unit.volumeLabel(TodayChecklistEngine.glassFluidOunces(for: unit)))")
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
    @FocusState private var isFieldFocused: Bool

    private var unit: MeasurementUnit { dataStore.profile.bodyMetrics.unit }

    /// Says why Save is disabled once something has been typed.
    private var rangeHint: String? {
        guard parsedKg == nil, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let range = DailyReminderEngine.plausibleWeightKilograms
        let low = unit.weightLabel(range.lowerBound, fractionDigits: 0)
        let high = unit.weightLabel(range.upperBound, fractionDigits: 0)
        return String(localized: "Enter a weight between \(low) and \(high).")
    }

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

            VStack(alignment: .leading, spacing: Spacing.xs) {
                GlassTextField(
                    placeholder: "Weight in \(unit.weightSuffix)",
                    text: $text,
                    icon: "scalemass.fill",
                    focus: $isFieldFocused
                )
                .keyboardType(.decimalPad)
                // Day-to-day weight moves by a few tenths, so starting from
                // the last entry beats typing the whole number again.
                if text.isEmpty, let last = dataStore.dedupedWeightHistory.last {
                    Button {
                        Haptics.selection()
                        text = unit.weightValue(last.kg, fractionDigits: 1...1)
                    } label: {
                        Label("Start from \(unit.weightLabel(last.kg, fractionDigits: 1))", systemImage: "arrow.uturn.backward")
                            .font(AppFont.chipText)
                            .foregroundStyle(AppColor.accentLight)
                            .minimumHitArea()
                    }
                    .buttonStyle(ScalePressStyle())
                }
                if let rangeHint {
                    Text(rangeHint)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.warning)
                }
            }

            GlassButton(title: "Save", icon: "checkmark", isFullWidth: true) {
                guard let kg = parsedKg else { return }
                dataStore.logWeight(kg: kg)
                Haptics.success()
                dismiss()
            }
            .disabled(parsedKg == nil)
        }
        .padding(Spacing.screenPadding)
        .onAppear { isFieldFocused = true }
        .liquidGlassPresentation(detents: [.medium])
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
            onAction: { _ in },
            supplements: [
                .init(supplement: Supplement(name: "Creatine", dose: "5 g", symbol: "bolt.fill"), isTaken: true),
                .init(supplement: Supplement(name: "Vitamin D", dose: "2 000 IE", symbol: "sun.max.fill"), isTaken: false),
            ],
            onToggleSupplement: { _ in },
            onManageSupplements: {}
        )
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
