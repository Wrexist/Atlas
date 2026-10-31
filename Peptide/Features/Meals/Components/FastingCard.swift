import SwiftUI

/// Compact fasting tracker on the Meals tab: a progress ring with the
/// time fasted, the current stage, and a one-tap Start / End. Tapping
/// the ring or text opens `FastingSheet` for presets, history and the
/// stage guide.
struct FastingCard: View {
    @State private var store = FastingStore.shared
    @State private var showSheet = false
    @State private var confirmsEarlyEnd = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
        .padding(Spacing.cardPadding)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        .task { store.load() }
        .sheet(isPresented: $showSheet) {
            FastingSheet()
                .liquidGlassPresentation()
        }
        .endFastEarlyConfirmation(isPresented: $confirmsEarlyEnd) { endFast() }
    }

    private func content(now: Date) -> some View {
        HStack(spacing: Spacing.md) {
            Button {
                showSheet = true
            } label: {
                HStack(spacing: Spacing.md) {
                    ring(now: now)
                    summary(now: now)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.98))
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens fasting presets, stages and history.")

            quickAction
        }
    }

    private func ring(now: Date) -> some View {
        let progress = store.active.map { FastingEngine.progress($0, at: now) } ?? 0
        return MetricRing(
            progress: progress,
            diameter: 64,
            strokeWidth: 7,
            gradient: [AppColor.accentDark, AppColor.accentPrimary, AppColor.accentLight],
            celebrateAtCompletion: true
        ) {
            if let active = store.active {
                Text(FastingEngine.clock(FastingEngine.elapsed(active, at: now)))
                    .font(AppFont.scaled(13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppColor.textPrimary)
            } else {
                Image(systemName: "moon.zzz.fill")
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .accessibilityHidden(true)
            }
        }
    }

    private func summary(now: Date) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Fasting")
                .font(AppFont.eyebrow)
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.accentLight)
            if let active = store.active {
                Text(FastingEngine.stage(of: active, at: now).title)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(activeSubtitle(active, now: now))
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                Text("Intermittent fasting")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(idleSubtitle(now: now))
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .multilineTextAlignment(.leading)
    }

    private var quickAction: some View {
        GlassButton(
            title: store.active == nil ? "Start" : "End",
            icon: store.active == nil ? "play.fill" : "stop.fill",
            style: .secondary
        ) {
            if store.active == nil {
                let last = store.lastPlan
                store.start(
                    plan: last.plan,
                    targetHours: last.hours,
                    remindsAtEnd: store.sessions.first?.remindsAtEnd ?? false
                )
                Haptics.impact(.medium)
            } else if let active = store.active, FastingEngine.remaining(active, at: Date()) > 0 {
                confirmsEarlyEnd = true
            } else {
                endFast()
            }
        }
        .accessibilityLabel(store.active == nil ? "Start fast" : "End fast")
    }

    private func endFast() {
        store.end()
        Haptics.success()
    }

    private func activeSubtitle(_ fast: FastSession, now: Date) -> String {
        let remaining = FastingEngine.remaining(fast, at: now)
        guard remaining > 0 else {
            return String(localized: "Goal reached · \(fast.plan.title)")
        }
        return String(localized: "\(FastingEngine.clock(remaining)) left · \(fast.plan.title)")
    }

    private func idleSubtitle(now: Date) -> String {
        // A fast finished today stays acknowledged for the rest of the
        // day instead of the card snapping straight back to "Start".
        if let last = store.ended.first, let endedAt = last.endedAt,
           Calendar.current.isDate(endedAt, inSameDayAs: now) {
            let duration = FastingEngine.clock(FastingEngine.elapsed(last, at: endedAt))
            return FastingEngine.metGoal(last)
                ? String(localized: "Fasted \(duration) today · goal reached")
                : String(localized: "Fasted \(duration) today")
        }
        let streak = FastingEngine.currentStreak(store.sessions, asOf: now, calendar: .current)
        if streak > 0 {
            return String(localized: "\(streak)-day streak · next: \(store.lastPlan.plan.title)")
        }
        return String(localized: "Start a \(store.lastPlan.plan.title) fast")
    }
}

extension View {
    /// Asks before ending a fast that hasn't reached its goal: one stray
    /// tap on End would otherwise throw away hours and the streak day.
    func endFastEarlyConfirmation(isPresented: Binding<Bool>, onEnd: @escaping () -> Void) -> some View {
        confirmationDialog("End fast early?", isPresented: isPresented, titleVisibility: .visible) {
            Button("End fast", role: .destructive, action: onEnd)
            Button("Keep fasting", role: .cancel) {}
        } message: {
            Text("It hasn't reached its goal yet, so it won't count toward your streak.")
        }
    }
}
