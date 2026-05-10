import SwiftUI
import UIKit

/// Hosts a scaled-down preview of the rendered cycle card, lets the user
/// flip the "include health data" toggle (off by default per the spec's
/// privacy guarantees), and pushes the final PNG through the iOS share
/// sheet. Reuses the `ShareSheet` representable already defined in
/// `Peptide/Features/Profile/Components/ExportSection.swift`.
struct ShareCardSheet: View {
    enum Subject {
        /// Per-protocol share — invoked from the Protocols tab card row
        /// and the protocol detail screen.
        case singleProtocol(PeptideProtocol)
        /// Stack-wide share — invoked from the Profile tab "Share my
        /// cycle card" button. Builds the model from every active
        /// protocol in the data store.
        case fullStack
    }

    let subject: Subject

    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore

    @State private var includeHealth = false
    @State private var healthSummary: CycleCardModel.HealthSummary?
    @State private var isLoadingHealth = false
    @State private var renderedURL: URL?
    @State private var showShareSheet = false
    @State private var isRendering = false
    @State private var errorMessage: String?

    private static let previewScale: CGFloat = 0.22
    private var previewWidth: CGFloat { ShareCardRenderer.canvasSize.width * Self.previewScale }
    private var previewHeight: CGFloat { ShareCardRenderer.canvasSize.height * Self.previewScale }

    private var baseModel: CycleCardModel {
        switch subject {
        case .singleProtocol(let proto):
            return CycleCardModel.forProtocol(proto, in: dataStore)
        case .fullStack:
            return CycleCardModel.forStack(in: dataStore)
        }
    }

    private var modelForRender: CycleCardModel {
        var m = baseModel
        if includeHealth, let healthSummary {
            m = CycleCardModel(
                subjectTitle: m.subjectTitle,
                peptides: m.peptides,
                activeSinceDate: m.activeSinceDate,
                cycleDay: m.cycleDay,
                cycleTotalDays: m.cycleTotalDays,
                dosesLogged: m.dosesLogged,
                adherencePercent: m.adherencePercent,
                currentStreakDays: m.currentStreakDays,
                healthSummary: healthSummary
            )
        }
        return m
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    preview
                    privacyToggle
                    pitch
                    GlassButton(
                        title: isRendering ? "Preparing…" : "Share Cycle Card",
                        icon: "square.and.arrow.up",
                        style: .primary,
                        isFullWidth: true
                    ) {
                        renderAndShare()
                    }
                    .disabled(isRendering)
                    .padding(.horizontal, Spacing.screenPadding)
                }
                .padding(.vertical, Spacing.xl)
            }
            .background(AppColor.background)
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let renderedURL {
                    ShareSheet(activityItems: [
                        renderedURL,
                        "Tracking my peptide protocol with PeptideX 🧬",
                    ])
                }
            }
            .alert("Couldn't share", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: includeHealth) { _, newValue in
                if newValue && healthSummary == nil {
                    Task { await loadHealthSummary() }
                }
            }
        }
    }

    // MARK: - Preview

    private var preview: some View {
        CycleCardView(model: modelForRender)
            .frame(
                width: ShareCardRenderer.canvasSize.width,
                height: ShareCardRenderer.canvasSize.height
            )
            .scaleEffect(Self.previewScale, anchor: .topLeading)
            .frame(width: previewWidth, height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
            )
            .shadow(color: AppColor.accentGlow, radius: 24, x: 0, y: 12)
    }

    // MARK: - Privacy toggle

    private var privacyToggle: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Toggle(isOn: $includeHealth) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "heart.text.square.fill")
                        .foregroundStyle(AppColor.accentLight)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include health signals")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Text("Adds weight delta, sleep, and HRV to the card.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            .toggleStyle(.switch)
            .tint(AppColor.accentPrimary)

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Off by default. Injection sites are never shared.")
                    .font(AppFont.caption)
            }
            .foregroundStyle(AppColor.textTertiary)

            if isLoadingHealth {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading health data…")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }
            }
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
        .padding(.horizontal, Spacing.screenPadding)
    }

    private var pitch: some View {
        VStack(spacing: Spacing.xs) {
            Text("1080 × 1920 · ready for Stories")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            Text("Brand watermark and QR are baked into the image.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
        }
    }

    // MARK: - Health data

    /// Pulls the spec'd metrics from `HealthKitService` plus the local
    /// weight history. Only runs when the user has flipped the toggle on,
    /// which itself implies they granted Apple Health permission earlier
    /// in onboarding (or via Profile). Failures degrade gracefully —
    /// missing fields render as nil and the corresponding card is hidden.
    @MainActor
    private func loadHealthSummary() async {
        guard dataStore.profile.healthConnected else {
            healthSummary = CycleCardModel.HealthSummary(
                weightDeltaKg: weightDeltaSinceCycleStart(),
                avgSleepHours: nil,
                hrvTrendDescription: nil
            )
            return
        }
        isLoadingHealth = true
        defer { isLoadingHealth = false }

        async let sleep = HealthKitService.shared.averageSleepHours(days: 7)
        async let hrv = HealthKitService.shared.averageHRV(days: 7)

        let sleepHours = await sleep
        let hrvAvg = await hrv

        healthSummary = CycleCardModel.HealthSummary(
            weightDeltaKg: weightDeltaSinceCycleStart(),
            avgSleepHours: sleepHours,
            hrvTrendDescription: hrvAvg.map { String(format: "%.0f ms avg", $0) }
        )
    }

    /// Difference between the most recent weight entry and the entry
    /// closest to the cycle's start date. Returns nil when the user has
    /// fewer than two entries — a single point is a "no trend" signal.
    private func weightDeltaSinceCycleStart() -> Double? {
        let history = dataStore.profile.weightHistory
        guard let last = history.last else { return nil }
        let cycleStart = baseModel.activeSinceDate
        let baseline = history
            .filter { $0.date <= cycleStart }
            .last
            ?? history.first
        guard let baseline, baseline.id != last.id else { return nil }
        return last.kg - baseline.kg
    }

    // MARK: - Render + share

    private func renderAndShare() {
        guard !isRendering else { return }
        isRendering = true
        // Render on the next runloop tick so the spinner state actually flushes
        // before the (synchronous) ImageRenderer pass kicks in.
        Task { @MainActor in
            await Task.yield()
            defer { isRendering = false }
            do {
                let url = try ShareCardRenderer.renderPNG(for: modelForRender)
                renderedURL = url
                if dataStore.profile.hapticFeedbackEnabled {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                showShareSheet = true
            } catch {
                if dataStore.profile.hapticFeedbackEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
