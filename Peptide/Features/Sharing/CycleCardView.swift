import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// Branded 1080×1350 share card. The watermark is intentionally a sibling
/// node inside the same root `ZStack` so `ImageRenderer` composites everything
/// in a single pass — the resulting PNG has no detachable layer for the
/// watermark and no detectable seam between content and footer.
struct CycleCardView: View {
    let proto: PeptideProtocol
    var showsQR: Bool = true

    private static let canvasWidth: CGFloat = 1080
    private static let canvasHeight: CGFloat = 1350
    private static let visiblePeptides = 6

    private var qrImage: UIImage? {
        guard showsQR else { return nil }
        return CycleCardView.qrCode(from: AppConstants.appStoreURL.absoluteString)
    }

    private var subtitle: String {
        let weeks = "\(proto.cycleLengthWeeks)-WEEK CYCLE"
        let count = "\(proto.peptides.count) PEPTIDE\(proto.peptides.count == 1 ? "" : "S")"
        let days = proto.schedule.compactDaysDescription.uppercased()
        return [weeks, count, days].joined(separator: "  ·  ")
    }

    private var displayURL: String {
        AppConstants.appStoreURL.absoluteString
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }

    private var attributionLine: String? {
        if let handle = proto.authorHandle, !handle.isEmpty {
            return "by \(handle)"
        }
        if let name = proto.authorName, !name.isEmpty {
            return "by \(name)"
        }
        return nil
    }

    var body: some View {
        ZStack {
            // 1. Brand gradient — bleeds through every part of the card so the
            //    watermark footer can never be cleanly cropped without losing
            //    background continuity.
            LinearGradient(
                colors: [
                    AppColor.accentDark,
                    AppColor.background,
                    AppColor.accentDark.opacity(0.6)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 2. Accent glow that extends behind both the body and the
            //    watermark, so cropping the bottom strip cuts into the visual.
            Circle()
                .fill(AppColor.accentPrimary.opacity(0.28))
                .frame(width: 800, height: 800)
                .blur(radius: 140)
                .offset(x: 220, y: -340)

            Circle()
                .fill(AppColor.accentLight.opacity(0.18))
                .frame(width: 600, height: 600)
                .blur(radius: 160)
                .offset(x: -260, y: 360)

            VStack(alignment: .leading, spacing: 0) {
                header
                hero
                peptideList
                Spacer(minLength: 0)
                watermark
            }
        }
        .frame(width: Self.canvasWidth, height: Self.canvasHeight)
        .clipped()
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let peptides = proto.peptides.map(\.abbreviation).joined(separator: ", ")
        let attribution = attributionLine.map { " " + $0 } ?? ""
        return "\(proto.name) cycle card.\(attribution) \(proto.cycleLengthWeeks)-week cycle. Peptides: \(peptides). Watermark: PeptideX."
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 14) {
                Image(systemName: "flask.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(AppColor.accentLight)
                Text("PEPTIDEX")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .tracking(6)
                    .foregroundStyle(.white)
            }
            Spacer()
            Text("CYCLE")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .tracking(4)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1)
                )
        }
        .padding(.top, 60)
        .padding(.horizontal, 60)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(proto.name)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.leading)

            Text(subtitle)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .tracking(2)
                .foregroundStyle(AppColor.accentLight)

            if let attributionLine {
                Text(attributionLine)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 60)
        .padding(.top, 36)
    }

    private var peptideList: some View {
        VStack(spacing: 16) {
            ForEach(proto.peptides.prefix(Self.visiblePeptides), id: \.id) { peptide in
                peptideRow(peptide)
            }

            if proto.peptides.count > Self.visiblePeptides {
                let extra = proto.peptides.count - Self.visiblePeptides
                Text("+ \(extra) more peptide\(extra == 1 ? "" : "s")")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }

            if proto.peptides.isEmpty {
                Text("No peptides yet")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            }
        }
        .padding(.horizontal, 60)
        .padding(.top, 44)
    }

    private func peptideRow(_ peptide: Peptide) -> some View {
        let schedule = proto.schedule(for: peptide.id)
        return HStack(spacing: 22) {
            Image(systemName: peptide.imageSystemName)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(peptide.category.color)
                .frame(width: 72, height: 72)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(peptide.category.color.opacity(0.22))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(peptide.abbreviation)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(schedule.summary)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }

            Spacer()

            Text(schedule.resolvedDose(for: peptide))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColor.accentLight)
                .lineLimit(1)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var watermark: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppConstants.watermarkText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(displayURL)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColor.accentLight)
            }

            Spacer()

            if let qrImage {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.white)
                    )
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 60)
        .padding(.vertical, 36)
        // Footer panel — gradient bleeds upward into the body, so cropping
        // the bottom strip leaves a hard black edge that breaks the card.
        .background(
            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - QR generation

    /// Generates a Core Image QR code as a UIImage so it can be composited
    /// inside the same SwiftUI view tree as the rest of the card.
    /// The returned image flows through `ImageRenderer` in the single render
    /// pass — no second-pass overlay.
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

#Preview {
    CycleCardView(proto: MockProtocols.recoveryStack)
        .scaleEffect(0.3)
        .frame(width: 324, height: 405)
        .preferredColorScheme(.dark)
}
