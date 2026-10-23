import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// Cycle share card, authored at the exact pixel size of its `ShareFormat`.
/// Pure SwiftUI so `ImageRenderer` can capture it deterministically — every
/// section (top bar, stack, stats, optional health, divider, watermark) is
/// a sibling inside the same root `ZStack` so the gradient background
/// bleeds through every element and there's no detachable layer for the
/// watermark. Story and square stack the sections in one column (square
/// tighter); landscape puts the stack left and the stats right.
struct CycleCardView: View {
    let model: CycleCardModel
    /// When true, compound names and abbreviations are masked behind
    /// "Compound A / B / C". The visual silhouettes / vial counts
    /// stay so the share still tells a story; the user just doesn't
    /// publish what they're running. Defaults to false — the call
    /// site decides based on the privacy toggle on ShareCardSheet
    /// (audit Sharing P1.8: the toggle previously only hid health
    /// metrics; compound names were always shown).
    var maskCompoundNames: Bool = false
    var format: ShareFormat = .story

    private static let maxVisibleVials = 4

    private var canvas: CGSize { format.pixelSize }
    private var metrics: Metrics { Metrics(format.layout) }

    var body: some View {
        ZStack {
            background

            content
                .padding(metrics.padding)
        }
        .frame(width: canvas.width, height: canvas.height)
        .clipped()
        .environment(\.colorScheme, .dark)
        // A fixed-size export: the sharer's own Dynamic Type size must not
        // resize the PNG's labels (at AX sizes they overflowed the stat
        // cards), so the canvas renders at the default size.
        .environment(\.dynamicTypeSize, .large)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Layout

    @ViewBuilder
    private var content: some View {
        switch format.layout {
        case .tall, .compact:
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
        case .wide:
            HStack(alignment: .top, spacing: 56) {
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                    stackSection
                    Spacer(minLength: 0)
                    watermark
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 0) {
                    statsColumn
                    if let health = model.healthSummary {
                        healthSection(health)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 440)
            }
        }
    }

    /// Spacing and sizes per layout. `.tall` is the original Stories card,
    /// unchanged; the others keep its proportions where they fit.
    private struct Metrics {
        let padding: CGFloat
        let sectionTop: CGFloat
        let vialsTop: CGFloat
        let vialsHeight: CGFloat
        let vialSize: CompoundVialSize
        let vialOverlap: CGFloat
        let stackSpacing: CGFloat
        let statsTop: CGFloat
        let healthTop: CGFloat
        let healthValueSize: CGFloat
        let healthCardPadding: CGFloat
        let dividerTop: CGFloat
        let dividerBottom: CGFloat
        let qrSize: CGFloat

        init(_ layout: ShareLayout) {
            switch layout {
            case .tall:
                padding = 80; sectionTop = 50; vialsTop = 40; vialsHeight = 200
                vialSize = .lg; vialOverlap = -28; stackSpacing = 28; statsTop = 60
                healthTop = 40; healthValueSize = 26; healthCardPadding = 20
                dividerTop = 40; dividerBottom = 36; qrSize = 96
            case .compact:
                padding = 64; sectionTop = 24; vialsTop = 16; vialsHeight = 200
                vialSize = .lg; vialOverlap = -28; stackSpacing = 20; statsTop = 32
                healthTop = 24; healthValueSize = 26; healthCardPadding = 20
                dividerTop = 24; dividerBottom = 20; qrSize = 72
            case .wide:
                // No divider in landscape — the watermark closes the left
                // column instead.
                padding = 56; sectionTop = 32; vialsTop = 8; vialsHeight = 150
                vialSize = .md; vialOverlap = -20; stackSpacing = 16; statsTop = 0
                healthTop = 24; healthValueSize = 22; healthCardPadding = 16
                dividerTop = 0; dividerBottom = 0; qrSize = 72
            }
        }
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
            // Sized against the shorter side and placed in proportion to
            // the canvas, so every format gets the same composition.
            Circle()
                .fill(Color(red: 0.310, green: 0.275, blue: 0.898).opacity(0.25))
                .frame(width: 900 * auraScale, height: 900 * auraScale)
                .blur(radius: 180 * auraScale)
                .offset(x: canvas.width * 240 / 1080, y: -canvas.height * 440 / 1920)

            Circle()
                .fill(Color(red: 0.486, green: 0.227, blue: 0.929).opacity(0.16))
                .frame(width: 700 * auraScale, height: 700 * auraScale)
                .blur(radius: 200 * auraScale)
                .offset(x: -canvas.width * 260 / 1080, y: canvas.height * 540 / 1920)
        }
    }

    private var auraScale: CGFloat { min(canvas.width, canvas.height) / 1080 }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center) {
            HStack(spacing: 16) {
                // The real brand mark, not a lab flask — every shared
                // image carries it.
                atlasMark(size: 48)
                Text("Atlas")
                    .font(AppFont.scaled(38, weight: .heavy, design: .rounded, in: .large))
                    .foregroundStyle(.white)
                    .tracking(-0.5)
            }
            Spacer()
            Text(displayTitle)
                .font(AppFont.scaled(20, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
                .lineLimit(1)
        }
    }

    // MARK: - Stack section

    private var stackSection: some View {
        VStack(alignment: .leading, spacing: metrics.stackSpacing) {
            vialsRow
                .padding(.top, metrics.vialsTop)

            if !model.peptides.isEmpty {
                Text(peptideNamesLine)
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Active since \(activeSinceFormatted)")
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                Text(cycleProgressLine)
                    .font(AppFont.scaled(28, weight: .bold, design: .rounded, in: .large))
                    .foregroundStyle(.white)
            }
        }
        .padding(.top, metrics.sectionTop)
    }

    private var vialsRow: some View {
        HStack(spacing: metrics.vialOverlap) {
            let visible = Array(model.peptides.prefix(Self.maxVisibleVials))
            ForEach(Array(visible.enumerated()), id: \.offset) { index, peptide in
                let label: String = maskCompoundNames
                    ? String(Character(UnicodeScalar(65 + index)!))
                    : peptide.abbreviation
                let displayName: String = maskCompoundNames
                    ? String(localized: "Compound \(label)")
                    : peptide.name
                CompoundVial(
                    compoundName: displayName,
                    category: peptide.category,
                    liquidLevel: 1.0,
                    labelText: label,
                    size: metrics.vialSize
                )
                .zIndex(Double(visible.count - index))
            }
            if model.peptides.count > Self.maxVisibleVials {
                let extra = model.peptides.count - Self.maxVisibleVials
                Text("+\(extra)")
                    .font(AppFont.scaled(32, weight: .bold, design: .rounded, in: .large))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .padding(.leading, 32)
            }
        }
        .frame(height: metrics.vialsHeight)
    }

    private var peptideNamesLine: String {
        if maskCompoundNames {
            // "Compound A · Compound B · …" — preserves the count
            // and the impression of stacking without naming the
            // specific compounds.
            let count = min(Self.maxVisibleVials, model.peptides.count)
            return (0..<count)
                .map { "Compound \(Character(UnicodeScalar(65 + $0)!))" }
                .joined(separator: " · ")
        }
        return model.peptides
            .prefix(Self.maxVisibleVials)
            .map(\.name)
            .joined(separator: ", ")
    }

    private var activeSinceFormatted: String {
        model.activeSinceDate.formatted(.dateTime.month(.wide).day().year())
    }

    /// "Day 0 of 84" read as a broken counter for a protocol that
    /// hasn't begun, and "Day 120 of 84" for one past its length; name
    /// the start date or the completed cycle instead.
    private var cycleProgressLine: String {
        guard model.cycleDay > 0 else { return String(localized: "Starts \(activeSinceFormatted)") }
        guard model.cycleDay <= model.cycleTotalDays else {
            return String(localized: "Cycle complete · \(model.cycleTotalDays) days")
        }
        return String(localized: "Day \(model.cycleDay) of \(model.cycleTotalDays) cycle")
    }

    private var streakLabel: String {
        model.currentStreakDays == 1 ? String(localized: "1 day") : String(localized: "\(model.currentStreakDays) days")
    }

    private func atlasMark(size: CGFloat) -> some View {
        Image("AtlasLogo")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 18) {
            statCard(value: dosesValue, label: String(localized: "Doses logged"))
            statCard(value: adherenceValue, label: String(localized: "Adherence"))
            statCard(value: streakLabel, label: String(localized: "Streak"), trailingGlyph: "🔥")
        }
        .padding(.top, metrics.statsTop)
    }

    /// Landscape: the same three stats as full-width rows, label left and
    /// figure right, so the right-hand column reads as a scoreboard.
    private var statsColumn: some View {
        VStack(spacing: 12) {
            statRow(value: dosesValue, label: "Doses logged")
            statRow(value: adherenceValue, label: "Adherence")
            statRow(value: streakLabel, label: "Streak", trailingGlyph: "🔥")
        }
    }

    private var dosesValue: String { "\(model.dosesLogged)" }
    private var adherenceValue: String { "\(model.adherencePercent)%" }

    private func statCard(value: String, label: String, trailingGlyph: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            statValue(value, size: 42, trailingGlyph: trailingGlyph)
            statLabel(label)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { statBackground }
    }

    private func statRow(value: String, label: String, trailingGlyph: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            statLabel(label)
            Spacer(minLength: 16)
            statValue(value, size: 36, trailingGlyph: trailingGlyph)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background { statBackground }
    }

    private func statValue(_ value: String, size: CGFloat, trailingGlyph: String?) -> some View {
        HStack(spacing: 6) {
            Text(value)
                .font(AppFont.scaled(size, weight: .bold, design: .rounded, in: .large))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let trailingGlyph {
                Text(trailingGlyph)
                    .font(AppFont.scaled(size * 5 / 7, in: .large))
            }
        }
    }

    private func statLabel(_ label: String) -> some View {
        Text(label)
            .font(AppFont.scaled(16, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.55))
            .textCase(.uppercase)
            .tracking(1.2)
    }

    private var statBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
    }

    // MARK: - Health section (only when toggled on)

    private func healthSection(_ summary: CycleCardModel.HealthSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Health signals")
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
                .textCase(.uppercase)
                .tracking(1.2)

            HStack(spacing: 18) {
                if let kg = summary.weightDeltaKg {
                    // In the sharer's own unit — an imperial user's card
                    // used to read "+1.8 kg".
                    let unit = summary.weightUnit
                    healthCard(
                        icon: kg >= 0 ? "arrow.up" : "arrow.down",
                        value: "\(kg >= 0 ? "+" : "")\(unit.weightValue(kg, fractionDigits: 1...1)) \(unit.weightSuffix)",
                        label: String(localized: "Weight")
                    )
                }
                if let hours = summary.avgSleepHours {
                    healthCard(
                        icon: "moon.fill",
                        value: "\(hours.formatted(.number.precision(.fractionLength(1)))) h",
                        label: String(localized: "Avg sleep")
                    )
                }
                if let trend = summary.hrvTrendDescription {
                    healthCard(
                        icon: "waveform.path.ecg",
                        value: trend,
                        label: String(localized: "HRV")
                    )
                }
            }
        }
        .padding(.top, metrics.healthTop)
    }

    private func healthCard(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(Color(red: 0.78, green: 0.74, blue: 0.96))
                Text(value)
                    .font(AppFont.scaled(metrics.healthValueSize, weight: .bold, design: .rounded, in: .large))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(label)
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .padding(metrics.healthCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
    }

    // MARK: - Divider + watermark

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(height: 1)
            .padding(.top, metrics.dividerTop)
            .padding(.bottom, metrics.dividerBottom)
    }

    private var watermark: some View {
        HStack(alignment: .center) {
            qrTile
            Spacer()
            HStack(spacing: 12) {
                atlasMark(size: 28)
                    .opacity(0.7)
                Text(AppConstants.watermarkText)
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var qrTile: some View {
        Group {
            if let qr = Self.appStoreQR {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: metrics.qrSize, height: metrics.qrSize)
            } else {
                RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
                    .fill(.white)
                    .frame(width: metrics.qrSize, height: metrics.qrSize)
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(.white)
        }
    }

    /// Protocols are often named after their compounds ("BPC-157 +
    /// TB-500"), so the mask hides the title as well as the vials.
    private var displayTitle: String {
        maskCompoundNames ? String(localized: "My Protocol") : model.subjectTitle
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        // Honour `maskCompoundNames` here too — a sighted user sees
        // "Compound A / B" while VoiceOver was reading the real
        // abbreviations, defeating the privacy point of the mask
        // (audit Sharing P2).
        let names: String
        if maskCompoundNames {
            names = model.peptides
                .enumerated()
                .map { idx, _ in
                    String(localized: "Compound ") + String(Character(UnicodeScalar(65 + idx)!))
                }
                .joined(separator: ", ")
        } else {
            names = model.peptides.map(\.abbreviation).joined(separator: ", ")
        }
        return String(localized: "\(displayTitle) cycle card. \(cycleProgressLine). ") +
               String(localized: "Peptides: \(names). ") +
               String(localized: "Doses logged: \(model.dosesLogged). Adherence: \(model.adherencePercent) percent. ") +
               String(localized: "Streak: \(streakLabel). Watermark: Atlas.")
    }

    // MARK: - QR generation

    /// Shared CIContext — constructing one is expensive and it's documented
    /// thread-safe, so we don't rebuild it on every render. `nonisolated(unsafe)`
    /// because `qrCode` runs under ImageRenderer off the main actor.
    nonisolated(unsafe) private static let ciContext = CIContext()

    /// The App Store link never changes, so the QR is generated once rather
    /// than on every preview render.
    private static let appStoreQR = qrCode(from: AppConstants.appStoreURL.absoluteString)

    /// Static so `ImageRenderer` doesn't trip over view-instance-bound state
    /// while it walks the tree to capture pixels.
    private static func qrCode(from string: String) -> UIImage? {
        let context = Self.ciContext
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
