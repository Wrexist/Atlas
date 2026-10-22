import SwiftUI

/// The pill at the bottom of the screen while a kept table is written —
/// "Adding 2 of 4 dishes…", then "4 dishes added" with a burst of
/// confetti. Reads `TableMomentStore.progress`, so any screen can mount
/// it and they all agree. A failed save stays up with Retry until the
/// user dismisses it — the scanned table exists nowhere else.
struct TableSaveToast: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(DataStore.self) private var dataStore
    private var store: TableMomentStore { TableMomentStore.shared }

    static let doneDuration: Duration = .milliseconds(2_400)

    var body: some View {
        ZStack(alignment: .bottom) {
            if store.progress?.outcome == .done, !reduceMotion {
                ConfettiView(
                    colors: [AppColor.accentPrimary, AppColor.accentLight, AppColor.success, AppColor.warning],
                    intensity: 70,
                    origin: UnitPoint(x: 0.5, y: 0.9)
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            if let progress = store.progress {
                pill(progress)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(store.progress != nil)
        .appAnimation(AppAnimation.toast, value: store.progress)
        .task(id: store.progress?.outcome) {
            guard store.progress?.outcome == .done else { return }
            try? await Task.sleep(for: Self.doneDuration)
            guard !Task.isCancelled else { return }
            AppAnimation.with(AppAnimation.toast) { store.clearProgress() }
        }
    }

    private func pill(_ progress: TableMomentStore.Progress) -> some View {
        HStack(spacing: Spacing.md) {
            icon(progress)
                .frame(width: 32, height: 32)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
                .id(progress.outcome)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(message(progress))
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                    .contentTransition(.numericText())
                if progress.outcome == nil {
                    ProgressView(value: Double(progress.saved), total: Double(max(progress.total, 1)))
                        .tint(AppColor.accentPrimary)
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 0)
            if progress.outcome == .failed {
                failureActions
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity)
        .glassControl(.rect(cornerRadius: Spacing.cardCornerRadius), interactive: false)
        .appShadow(AppShadow.toast)
        .accessibilityElement(children: progress.outcome == .failed ? .contain : .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var failureActions: some View {
        HStack(spacing: Spacing.sm) {
            Button("Retry") {
                Task { await store.retryFailedKeep(in: dataStore) }
            }
            .font(AppFont.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(AppColor.accentLight)
            .minimumHitArea()
            Button {
                AppAnimation.with(AppAnimation.toast) { store.clearProgress() }
            } label: {
                Image(systemName: "xmark")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .minimumHitArea()
            }
            .accessibilityLabel("Dismiss")
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func icon(_ progress: TableMomentStore.Progress) -> some View {
        switch progress.outcome {
        case .done:
            Image(systemName: "checkmark")
                .font(AppFont.scaled(13, weight: .bold))
                .foregroundStyle(AppColor.onAccent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(AppColor.accentFill))
                .completionPulse(trigger: progress.total)
                .accessibilityHidden(true)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(AppColor.warning)
                .accessibilityHidden(true)
        case nil:
            ProgressView()
                .tint(AppColor.accentPrimary)
        }
    }

    private func message(_ progress: TableMomentStore.Progress) -> String {
        switch progress.outcome {
        case .done:
            progress.total == 1
                ? String(localized: "1 dish added")
                : String(localized: "\(progress.total) dishes added")
        case .failed:
            String(localized: "Couldn't save the table.")
        case nil:
            String(localized: "Adding \(min(progress.saved + 1, progress.total)) of \(progress.total) dishes…")
        }
    }
}
