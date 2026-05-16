import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// 1080×1920 share card sized for Instagram Stories. Pure SwiftUI so
/// `ImageRenderer` can capture it deterministically — every section
/// (top bar, stack, stats, optional health, divider, watermark) is a
/// sibling inside the same root `ZStack` so the gradient background
/// bleeds through every element and there's no detachable layer for
/// the watermark.
struct CycleCardView: View {
    let model: CycleCardModel

    private static let canvasWidth: CGFloat = 1080
    private static let canvasHeight: CGFloat = 1920
    private static let maxVisibleVials = 4

    var body: some View {
        ZStack {
            background

            VStack(alignment: .leading, spacing: 0) {
                topBar
                stackSection
                statsRow
                if let health = model.healthSummary {
                    healthSection(health)
                }
                Spacer(minLength: 0)
                divider
                watermark
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 80)
        }
        .frame(width: Self.canvasWidth, height: Self.canvasHeight)
        .clipped()
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.051, green: 0.051, blue: 0.102), // #0D0D1A
                    Color(red: 0.102, green: 0.039, blue: 0.180), // #1A0A2E
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Soft purple aura — bleeds across both stack + watermark so
            // the watermark can't be cropped out without leaving a hard edge.
            Circle()
                .fill(Color(red: 0.310, green: 0.275, blue: 0.898).opacity(0.25))
                .frame(width: 900, height: 900)
                .blur(radius: 180)
                .offset(x: 240, y: -440)

            Circle()
                .fill(Color(red: 0.486, green: 0.227, blue: 0.929).opacity(0.16))
                .frame(width: 700, height: 700)
                .blur(radius: 200)
                .offset(x: -260, y: 540)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center) {
            HStack(spacing: 16) {
                Image(systemName: "flask.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.white, Color(red: 0.78, green: 0.74, blue: 0.96)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .accessibilityHidden(true)
                Text("Atlas")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(-0.5)
            }
            Spacer()
            Text(model.subjectTitle)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
                .lineLimit(1)
        }
    }

    // MARK: - Stack section

    private var stackSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            vialsRow
                .padding(.top, 40)

            if !model.peptides.isEmpty {
                Text(peptideNamesLine)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Active since \(activeSinceFormatted)")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                Text("Day \(model.cycleDay) of \(model.cycleTotalDays) cycle")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .padding(.top, 50)
    }

    private var vialsRow: some View {
        HStack(spacing: -28) {
            let visible = Array(model.peptides.prefix(Self.maxVisibleVials))
            ForEach(Array(visible.enumerated()), id: \.offset) { index, peptide in
                CompoundVial(
                    compoundName: peptide.name,
                    category: peptide.category,
                    liquidLevel: 1.0,
                    labelText: peptide.abbreviation,
                    size: .lg
                )
                .zIndex(Double(visible.count - index))
            }
            if model.peptides.count > Self.maxVisibleVials {
                let extra = model.peptides.count - Self.maxVisibleVials
                Text("+\(extra)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .padding(.leading, 32)
            }
        }
        .frame(height: 200)
    }

    private var peptideNamesLine: String {
        model.peptides
            .prefix(Self.maxVisibleVials)
            .map(\.name)
            .joined(separator: ", ")
    }

    private var activeSinceFormatted: String {
        model.activeSinceDate.formatted(.dateTime.month(.wide).day().year())
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 18) {
            statCard(
                value: "\(model.dosesLogged)",
                label: "Doses logged"
            )
            statCard(
                value: "\(model.adherencePercent)%",
                label: "Adherence"
            )
            statCard(
                value: "\(model.currentStreakDays) days",
                label: "Streak",
                trailingGlyph: "🔥"
            )
        }
        .padding(.top, 60)
    }

    private func statCard(value: String, label: String, trailingGlyph: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let trailingGlyph {
                    Text(trailingGlyph)
                        .font(.system(size: 30))
                }
            }
            Text(label)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
                .textCase(.uppercase)
                .tracking(1.2)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
    }

    // MARK: - Health section (only when toggled on)

    private func healthSection(_ summary: CycleCardModel.HealthSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Health signals")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
                .textCase(.uppercase)
                .tracking(1.2)

            HStack(spacing: 18) {
                if let kg = summary.weightDeltaKg {
                    healthCard(
                        icon: kg >= 0 ? "arrow.up" : "arrow.down",
                        value: String(format: "%@%.1f kg", kg >= 0 ? "+" : "", kg),
                        label: "Weight"
                    )
                }
                if let hours = summary.avgSleepHours {
                    healthCard(
                        icon: "moon.fill",
                        value: String(format: "%.1f h", hours),
                        label: "Avg sleep"
                    )
                }
                if let trend = summary.hrvTrendDescription {
                    healthCard(
                        icon: "waveform.path.ecg",
                        value: trend,
                        label: "HRV"
                    )
                }
            }
        }
        .padding(.top, 40)
    }

    private func healthCard(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(red: 0.78, green: 0.74, blue: 0.96))
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(label)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
    }

    // MARK: - Divider + watermark

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(height: 1)
            .padding(.top, 40)
            .padding(.bottom, 36)
    }

    private var watermark: some View {
        HStack(alignment: .center) {
            qrTile
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: "flask.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(AppConstants.watermarkText)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var qrTile: some View {
        Group {
            if let qr = Self.qrCode(from: AppConstants.appStoreURL.absoluteString) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 96, height: 96)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white)
                    .frame(width: 96, height: 96)
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white)
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        let names = model.peptides.map(\.abbreviation).joined(separator: ", ")
        return "\(model.subjectTitle) cycle card. Day \(model.cycleDay) of \(model.cycleTotalDays). " +
               "Peptides: \(names). " +
               "Doses logged: \(model.dosesLogged). Adherence: \(model.adherencePercent) percent. " +
               "Streak: \(model.currentStreakDays) days. Watermark: Atlas."
    }

    // MARK: - QR generation

    /// Static so `ImageRenderer` doesn't trip over view-instance-bound state
    /// while it walks the tree to capture pixels.
    private static func qrCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }
        let target: CGFloat = 240
        let scale = target / max(output.extent.width, 1)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
