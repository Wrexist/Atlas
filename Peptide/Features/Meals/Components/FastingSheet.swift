import SwiftUI

/// Full fasting tracker: preset picker and Start while idle; live ring,
/// adjustable start time, reminder and End while fasting; then the
/// general-information stage guide and the history with streaks.
struct FastingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = FastingStore.shared
    @State private var plan: FastingProtocol = .sixteen
    @State private var customHours: Double = FastingProtocol.custom.defaultFastingHours
    @State private var remindsAtEnd = false

    private var targetHours: Double {
        plan == .custom ? customHours : plan.defaultFastingHours
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        hero(now: context.date)
                        if let active = store.active {
                            activeControls(active)
                        } else {
                            planPicker
                            reminderToggle
                            PrimaryCTAButton(title: "Start fast", icon: "play.fill", action: startFast)
                        }
                        stageGuide(now: context.date)
                        history(now: context.date)
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.lg)
                .readableContentWidth()
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("Fasting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: seedFromHistory)
        }
    }

    // MARK: - Hero

    private func hero(now: Date) -> some View {
        let active = store.active
        let progress = active.map { FastingEngine.progress($0, at: now) } ?? 0
        return VStack(spacing: Spacing.md) {
            MetricRing(
                progress: progress,
                diameter: 200,
                strokeWidth: 16,
                gradient: [AppColor.accentDark, AppColor.accentPrimary, AppColor.accentLight],
                celebrateAtCompletion: true
            ) {
                VStack(spacing: Spacing.xxs) {
                    Text(active == nil ? "Ready" : "Elapsed")
                        .font(AppFont.eyebrow)
                        .textCase(.uppercase)
                        .foregroundStyle(AppColor.textSecondary)
                    Text(FastingEngine.clock(active.map { FastingEngine.elapsed($0, at: now) } ?? 0))
                        .font(AppFont.statValueSmall)
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                    Text(heroCaption(active, now: now))
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)

            if let active {
                Label(FastingEngine.stage(of: active, at: now).title,
                      systemImage: FastingEngine.stage(of: active, at: now).icon)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.accentLight)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.sm)
    }

    private func heroCaption(_ active: FastSession?, now: Date) -> String {
        guard let active else {
            return String(localized: "Goal \(Int(targetHours)) h")
        }
        let remaining = FastingEngine.remaining(active, at: now)
        guard remaining > 0 else { return String(localized: "Goal reached") }
        return String(localized: "\(FastingEngine.clock(remaining)) to \(Int(active.targetHours)) h")
    }

    // MARK: - Controls

    private var planPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("Plan")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(FastingProtocol.allCases) { option in
                        GlassChip(LocalizedStringKey(option.title), isSelected: plan == option) {
                            plan = option
                        }
                    }
                }
            }
            if plan == .custom {
                Stepper(value: $customHours, in: FastingEngine.customHoursRange, step: 1) {
                    Text("\(Int(customHours)) h fast")
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)
                }
            } else {
                Text("Fast \(Int(plan.defaultFastingHours)) h, eat within \(24 - Int(plan.defaultFastingHours)) h.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    private var reminderToggle: some View {
        Toggle(isOn: Binding(
            get: { store.active?.remindsAtEnd ?? remindsAtEnd },
            set: setReminder
        )) {
            Text("Notify me when the fast ends")
                .font(AppFont.body)
                .foregroundStyle(AppColor.textPrimary)
        }
        .tint(AppColor.accentPrimary)
    }

    private func activeControls(_ active: FastSession) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            DatePicker(
                "Started",
                selection: Binding(
                    get: { active.startedAt },
                    set: { store.updateStart($0) }
                ),
                in: ...Date(),
                displayedComponents: [.date, .hourAndMinute]
            )
            .font(AppFont.body)
            .foregroundStyle(AppColor.textPrimary)
            reminderToggle
            PrimaryCTAButton(title: "End fast", icon: "stop.fill") {
                store.end()
                Haptics.success()
            }
        }
    }

    // MARK: - Stage guide

    private func stageGuide(now: Date) -> some View {
        let current = store.active.map { FastingEngine.stage(of: $0, at: now) }
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("Stages")
            ForEach(FastingEngine.Stage.allCases) { stage in
                FastingStageRow(stage: stage, isCurrent: stage == current)
            }
            Text("General information, not medical advice. Timing varies from person to person. Talk to a clinician before fasting if you're pregnant, diabetic, have a history of disordered eating, or take medication.")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - History

    private func history(now: Date) -> some View {
        let ended = store.ended
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("History")
            HStack(spacing: Spacing.sm) {
                StatTile(
                    label: "Streak",
                    value: "\(FastingEngine.currentStreak(store.sessions, asOf: now, calendar: .current))"
                )
                StatTile(
                    label: "Best",
                    value: "\(FastingEngine.bestStreak(store.sessions, calendar: .current))"
                )
                StatTile(
                    label: "7-fast avg",
                    value: FastingEngine.averageDuration(store.sessions).map(FastingEngine.clock) ?? "–"
                )
            }
            if ended.isEmpty {
                Text("Finished fasts show up here. A day counts toward your streak when a fast reaches its goal.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                ForEach(ended.prefix(20)) { fast in
                    FastHistoryRow(fast: fast)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                store.delete(id: fast.id)
                            }
                        }
                }
            }
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(AppFont.title3)
            .foregroundStyle(AppColor.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Actions

    private func seedFromHistory() {
        let last = store.lastPlan
        plan = last.plan
        customHours = last.hours
        remindsAtEnd = store.sessions.first?.remindsAtEnd ?? false
    }

    private func startFast() {
        store.start(plan: plan, targetHours: targetHours, remindsAtEnd: remindsAtEnd)
        Haptics.impact(.medium)
    }

    private func setReminder(_ enabled: Bool) {
        if store.active != nil {
            store.setReminder(enabled)
        } else {
            remindsAtEnd = enabled
        }
        guard enabled else { return }
        Task { _ = await NotificationService.shared.requestAuthorization() }
    }
}

private struct FastingStageRow: View {
    let stage: FastingEngine.Stage
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: stage.icon)
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(isCurrent ? AppColor.accentLight : AppColor.textSecondary)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack {
                    Text(stage.title)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer(minLength: 0)
                    Text("\(Int(stage.startHour)) h+")
                        .font(AppFont.caption2)
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textSecondary)
                }
                Text(stage.detail)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.md)
        .insetRowBackground(
            cornerRadius: Spacing.smallCornerRadius,
            border: isCurrent ? AppColor.accentPrimary : AppColor.glassBorder
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

private struct FastHistoryRow: View {
    let fast: FastSession

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: FastingEngine.metGoal(fast) ? "checkmark.circle.fill" : "circle.dashed")
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(FastingEngine.metGoal(fast) ? AppColor.positive : AppColor.textTertiary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(fast.startedAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("\(fast.plan.title) · goal \(Int(fast.targetHours)) h")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: 0)
            Text(FastingEngine.clock(FastingEngine.elapsed(fast, at: fast.endedAt ?? fast.startedAt)))
                .font(AppFont.headline)
                .monospacedDigit()
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(Spacing.md)
        .insetRowBackground(cornerRadius: Spacing.smallCornerRadius)
        .accessibilityElement(children: .combine)
        .accessibilityValue(FastingEngine.metGoal(fast) ? "Goal reached" : "Ended early")
    }
}
