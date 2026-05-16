import SwiftUI

/// Developer-facing diagnostics row in Profile. Surfaces the
/// MetricKit subscription's captured payload count so the wiring
/// is visible without leaving the device, and offers a tap-in
/// sheet showing the latest 20 records (kind, timestamp, raw JSON
/// preview).
///
/// Apple's TestFlight + App Store Connect dashboards collect the
/// same data on the server side — this is the offline / on-device
/// view that doesn't require leaving the app.
struct DiagnosticsSection: View {
    @State private var diagnosticsService = DiagnosticsService.shared
    @State private var showDetail = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Diagnostics", systemImage: "waveform.path.ecg.rectangle.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                Button {
                    showDetail = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MetricKit reports")
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textPrimary)
                            Text(detailSummary)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(diagnosticsService.records.isEmpty)
            }
        }
        .sheet(isPresented: $showDetail) {
            DiagnosticsDetailSheet(service: diagnosticsService)
        }
    }

    private var detailSummary: String {
        let total = diagnosticsService.records.count
        if total == 0 {
            return String(localized: "No reports captured yet — appears after first crash or hang.")
        }
        let crashCount = diagnosticsService.records.filter { $0.kind == .diagnostic }.count
        let metricCount = total - crashCount
        return "\(crashCount) diagnostic · \(metricCount) metric · last \(relativeTime(for: diagnosticsService.records[0].receivedAt))"
    }

    private func relativeTime(for date: Date) -> String {
        Self.formatter.localizedString(for: date, relativeTo: Date())
    }

    nonisolated(unsafe) private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}

// MARK: - Detail sheet

private struct DiagnosticsDetailSheet: View {
    @Bindable var service: DiagnosticsService
    @Environment(\.dismiss) private var dismiss
    @State private var showConfirmClear = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Spacing.sm) {
                    if service.records.isEmpty {
                        emptyState
                    } else {
                        ForEach(service.records) { record in
                            recordCard(record)
                        }
                    }
                }
                .padding(Spacing.screenPadding)
            }
            .background(AppColor.background)
            .navigationTitle("MetricKit Reports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !service.records.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            showConfirmClear = true
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .confirmationDialog(
                "Clear all reports?",
                isPresented: $showConfirmClear,
                titleVisibility: .visible
            ) {
                Button("Clear", role: .destructive) {
                    service.reset()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes the captured MetricKit payloads from this device. Apple's server-side TestFlight crash data is unaffected.")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(AppColor.success)
                .padding(.top, Spacing.xxl)
            Text("No reports yet")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("MetricKit delivers daily payloads on launch after a crash or hang. Once captured, they show up here.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
        }
    }

    private func recordCard(_ record: DiagnosticsService.Record) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Label(record.kind == .diagnostic ? "Diagnostic" : "Metric",
                      systemImage: record.kind == .diagnostic ? "exclamationmark.triangle.fill" : "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(record.kind == .diagnostic ? AppColor.warning : AppColor.accentLight)
                Spacer()
                Text(record.receivedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Text(payloadPreview(for: record))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.sm)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .fill(AppColor.surfaceElevated.opacity(0.5))
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
    }

    private func payloadPreview(for record: DiagnosticsService.Record) -> String {
        // Truncate to ~480 chars so a 50KB MetricKit payload doesn't
        // blow up the row. Full payload is on disk for any future
        // upload path.
        let raw = String(data: record.payloadJSON, encoding: .utf8) ?? "<binary>"
        if raw.count > 480 {
            let prefix = raw.prefix(480)
            return "\(prefix)…"
        }
        return raw
    }
}
