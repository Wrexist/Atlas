import SwiftUI

/// One row on the Biology tab's biomarker list. Left side: trend
/// badge (icon in a tinted circle, direction arrow overlay) +
/// name + "Increasing · 72.0 kg" subtitle. Right side: inline
/// sparkline. Tappable — the host wires the tap to
/// `BiomarkerDetailSheet` (commit 8) for the 90-day chart view.
///
/// Layout mirrors Bevel's biomarker rows: small footprint per row
/// (~64pt tall) so 4–6 cards fit on a phone screen without
/// scrolling, scannable enough that the user reads "weight up,
/// HRV holding, RHR down" in a single glance.
struct BiomarkerRow: View {
    let snapshot: BiomarkerSnapshot
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                trendBadge

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.biomarker.displayName)
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)

                    Text(snapshot.changeText)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: Spacing.sm)

                if snapshot.sparkline.count >= 2 {
                    BiomarkerSparkline(
                        points: snapshot.sparkline,
                        tint: sparklineTint
                    )
                    .frame(width: 64)
                } else {
                    // Nothing to plot yet, so the right edge carries the
                    // affordance instead: this row opens a screen where
                    // the user can add the reading.
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                }
            }
            .padding(Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.55))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Trend badge

    /// Rounded-square tile rather than a disc: it sits in a column of
    /// rounded-rectangle rows, and the concentric radius makes the tile
    /// read as part of the row instead of a sticker on top of it.
    private var trendBadge: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: Spacing.concentric(in: Spacing.cardCornerRadius,
                                                 inset: Spacing.md),
                style: .continuous
            )
            .fill(badgeTint.opacity(0.20))

            Image(systemName: snapshot.biomarker.icon)
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(badgeTint)

            // Direction arrow in a tiny notch — only when there's
            // a meaningful trend. Keeps the badge clean when the
            // tile has no series (blood pressure, etc.).
            if let arrow = trendArrow {
                Image(systemName: arrow)
                    .font(AppFont.scaled(8, weight: .heavy))
                    .foregroundStyle(AppColor.background)
                    .padding(2)
                    .background {
                        Circle().fill(badgeTint)
                    }
                    .offset(x: 14, y: 14)
            }
        }
        .frame(width: 40, height: 40)
    }

    /// Direction arrow shown in the badge corner. `nil` for flat
    /// / insufficient — those are quieter states and don't need
    /// a chevron screaming at the user.
    private var trendArrow: String? {
        switch snapshot.trend {
        case .up:           return "arrow.up"
        case .down:         return "arrow.down"
        case .flat:         return nil
        case .insufficient: return nil
        }
    }

    /// Badge tint follows the biomarker family. Drives both the
    /// icon background and the corner-arrow fill so the row
    /// reads as one chip, not two unrelated shapes.
    private var badgeTint: Color {
        switch snapshot.biomarker {
        case .weight:           return AppColor.macroProtein
        case .hrvBaseline:      return AppColor.metricHRV
        case .rhrBaseline:      return AppColor.metricHeartRate
        case .sleepBaseline:    return AppColor.metricSleep
        case .stepsBaseline:    return AppColor.metricActivity
        case .bodyTemperature:  return AppColor.warning
        case .bodyFat:          return AppColor.streak
        case .waist:            return AppColor.accentLight
        case .bloodPressure:    return AppColor.destructive
        case .latestLabPanel:   return AppColor.accentPrimary
        }
    }

    /// Sparkline tint matches the badge for a single colour
    /// story per row. The fill underneath is the same colour at
    /// reduced opacity; the gradient handles the depth.
    private var sparklineTint: Color { badgeTint }
}
