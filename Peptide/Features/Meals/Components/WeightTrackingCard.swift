import SwiftUI

/// Weight-tracking card on the Lifestyle tab — header with the trend
/// badge, 14-day sparkline, "Log weight" pill on the right. The
/// sparkline is hand-rolled so it carries the brand gradient instead of
/// the default Charts framework styling and stays purely SwiftUI without
/// pulling in Apple's Charts (which is iOS 16+ only and themes more
/// loosely than this surface needs).
struct WeightTrackingCard: View {
    let history: [WeightEntry]
    let unit: MeasurementUnit
    let onLog: () -> Void

    private static let windowDays = 14

    private var sparklinePoints: [WeightEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.windowDays, to: Date()) ?? Date()
        return history.filter { $0.date >= cutoff }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header

            if sparklinePoints.isEmpty {
                emptyState
            } else {
                Sparkline(points: sparklinePoints, unit: unit)
                    .frame(height: 70)
                trendBadge
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassControl(.rect(cornerRadius: Spacing.cardCornerRadius))
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Label {
                Text("Weight Tracking")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
            } icon: {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(AppColor.accentPrimary)
            }

            Spacer(minLength: 0)

            Button(action: onLog) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(11, weight: .bold))
                    Text("Log weight")
                        .font(AppFont.scaled(11, weight: .semibold))
                }
                .foregroundStyle(AppColor.onAccent)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 7)
                .background {
                    Capsule(style: .continuous)
                        .fill(AppColor.accentFill)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(AppColor.onAccent.opacity(0.18), lineWidth: 0.5)
                        }
                }
                .shadow(color: AppColor.accentPrimary.opacity(0.45), radius: 8, y: 3)
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.95))
        }
    }

    private var emptyState: some View {
        Text("No entries yet — tap Log weight to start a trend.")
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Spacing.sm)
    }

    private var trendBadge: some View {
        // Use the same 14-day slice the sparkline renders so the badge
        // never reports a delta against a baseline that's off-screen.
        let delta = WeightTrend.weeklyDelta(in: sparklinePoints)
        let format = unitFormatter()
        return HStack(spacing: 4) {
            Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(AppFont.scaled(11, weight: .bold))
            Text(format(abs(delta)) + " this week")
                .font(AppFont.scaled(11, weight: .semibold))
        }
        .foregroundStyle(delta == 0 ? AppColor.textSecondary : (delta > 0 ? AppColor.negative : AppColor.accentPrimary))
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 3)
        .background {
            Capsule()
                .fill(AppColor.surfaceElevated)
        }
    }

    private func unitFormatter() -> (Double) -> String {
        return { kg in unit.weightLabel(kg, fractionDigits: 1) }
    }
}

// MARK: - Sparkline

private struct Sparkline: View {
    let points: [WeightEntry]
    let unit: MeasurementUnit

    var body: some View {
        GeometryReader { proxy in
            let values = points.map { $0.kg }
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 0
            let span = max(0.5, maxV - minV)
            let path = Path { p in
                guard !values.isEmpty else { return }
                let stepX = points.count > 1
                    ? proxy.size.width / CGFloat(points.count - 1)
                    : proxy.size.width
                for (index, kg) in values.enumerated() {
                    let normalised = CGFloat((kg - minV) / span)
                    let x = stepX * CGFloat(index)
                    let y = proxy.size.height * (1 - normalised) * 0.85 + proxy.size.height * 0.075
                    if index == 0 {
                        p.move(to: CGPoint(x: x, y: y))
                    } else {
                        p.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }

            ZStack {
                path.stroke(
                    LinearGradient(
                        colors: [AppColor.accentLight, AppColor.accentPrimary],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
                if let last = points.last {
                    let stepX = points.count > 1
                        ? proxy.size.width / CGFloat(points.count - 1)
                        : proxy.size.width
                    let normalised = CGFloat((last.kg - minV) / span)
                    let x = stepX * CGFloat(points.count - 1)
                    let y = proxy.size.height * (1 - normalised) * 0.85 + proxy.size.height * 0.075
                    Circle()
                        .fill(AppColor.accentPrimary)
                        .frame(width: 8, height: 8)
                        .position(x: x, y: y)
                }
            }
            .accessibilityLabel(accessibilitySummary)
        }
    }

    private var accessibilitySummary: String {
        guard let first = points.first?.kg, let last = points.last?.kg else { return "No data" }
        let delta = last - first
        return String(localized: "Weight changed \(unit.weightLabel(delta, fractionDigits: 1)) over the window")
    }
}

// MARK: - Trend math

enum WeightTrend {
    /// Difference between the last entry and the most recent entry that
    /// is more than 7 days older. Returns 0 when there's no point at
    /// least a week behind the last one — avoids reporting a misleading
    /// "0.0 kg this week" when the user only logged one weight ever.
    static func weeklyDelta(in history: [WeightEntry]) -> Double {
        guard let last = history.last else { return 0 }
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: last.date) ?? last.date
        guard let baseline = history.last(where: { $0.date <= weekAgo }) else { return 0 }
        return last.kg - baseline.kg
    }
}
