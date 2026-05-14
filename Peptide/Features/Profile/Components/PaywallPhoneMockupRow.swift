import SwiftUI

/// Trio of stylised iPhone frames sitting under the paywall hero. Centre
/// frame stands upright, outer two tilt 8° outward to give a fanned
/// silhouette. Each frame renders a representative slice of the app
/// (Home dose log, half-life chart, cycle card) using SwiftUI primitives
/// — dropping in actual screenshots is a follow-up that needs a snapshot
/// pipeline and the asset slots wired into the catalog.
struct PaywallPhoneMockupRow: View {
    var body: some View {
        HStack(spacing: -28) {
            phoneFrame(.home)
                .scaleEffect(0.86)
                .rotationEffect(.degrees(-8))
                .offset(y: 12)
                .zIndex(1)

            phoneFrame(.halfLife)
                .scaleEffect(0.96)
                .zIndex(3)

            phoneFrame(.cycleCard)
                .scaleEffect(0.86)
                .rotationEffect(.degrees(8))
                .offset(y: 12)
                .zIndex(2)
        }
        .frame(height: 230)
    }

    private func phoneFrame(_ kind: MockupKind) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(AppColor.background)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.22),
                                    Color.white.opacity(0.04),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                }
                .shadow(color: .black.opacity(0.55), radius: 16, x: 0, y: 12)

            mockContent(for: kind)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(6)

            // Notch — small pill at the top to read as an iPhone silhouette.
            Capsule()
                .fill(Color.black)
                .frame(width: 60, height: 14)
                .offset(y: -100)
        }
        .frame(width: 130, height: 220)
    }

    /// Tries the corresponding asset-catalog screenshot first
    /// (`paywall-home`, `paywall-halflife`, `paywall-cyclecard`).
    /// Falls back to the hand-built SwiftUI mock when the asset is
    /// missing so the paywall always renders, even before the
    /// snapshot pipeline runs. Drop a 1170×2532 PNG (3x of
    /// 390×844) into Assets.xcassets under any of the three names
    /// above and it'll replace its mock on the next launch.
    @ViewBuilder
    private func mockContent(for kind: MockupKind) -> some View {
        if let uiImage = UIImage(named: kind.assetName) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            switch kind {
            case .home:      HomeMock()
            case .halfLife:  HalfLifeMock()
            case .cycleCard: CycleCardMock()
            }
        }
    }

    private enum MockupKind {
        case home, halfLife, cycleCard

        /// Asset-catalog name the mockup row tries to load before
        /// falling back to the SwiftUI mock. Keep these stable —
        /// the snapshot pipeline writes PNGs under these exact names.
        var assetName: String {
            switch self {
            case .home:      "paywall-home"
            case .halfLife:  "paywall-halflife"
            case .cycleCard: "paywall-cyclecard"
            }
        }
    }
}

// MARK: - Stylised in-frame content

private struct HomeMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(AppColor.textSecondary)

            mockDoseRow(label: "BPC-157", time: "8:00 AM", done: true)
            mockDoseRow(label: "TB-500",  time: "1:00 PM", done: true)
            mockDoseRow(label: "Sema",    time: "9:00 PM", done: false)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Capsule().fill(AppColor.accentPrimary).frame(width: 28, height: 4)
                Capsule().fill(AppColor.glassBorder).frame(width: 8, height: 4)
                Capsule().fill(AppColor.glassBorder).frame(width: 8, height: 4)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.surfaceSecondary.opacity(0.6))
    }

    private func mockDoseRow(label: String, time: String, done: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(done ? AppColor.accentPrimary : AppColor.textTertiary)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text(time)
                    .font(.system(size: 7))
                    .foregroundStyle(AppColor.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(AppColor.surfaceElevated)
        }
    }
}

private struct HalfLifeMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Half-life")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(AppColor.accentLight)

            ZStack {
                GeometryReader { proxy in
                    halfLifePath(in: proxy.size, peakAt: 0.25)
                        .stroke(AppColor.accentPrimary, lineWidth: 1.5)
                    halfLifePath(in: proxy.size, peakAt: 0.55)
                        .stroke(AppColor.accentLight.opacity(0.7), lineWidth: 1.5)
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                Text("0h")
                Spacer()
                Text("24h")
            }
            .font(.system(size: 7))
            .foregroundStyle(AppColor.textTertiary)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.surfaceSecondary.opacity(0.6))
    }

    private func halfLifePath(in size: CGSize, peakAt t: CGFloat) -> Path {
        let baseline = size.height * 0.85
        let peakY = size.height * 0.20
        return Path { path in
            path.move(to: CGPoint(x: 0, y: baseline))
            path.addCurve(
                to: CGPoint(x: size.width, y: baseline),
                control1: CGPoint(x: size.width * t, y: peakY),
                control2: CGPoint(x: size.width * (t + 0.4), y: baseline * 0.95)
            )
        }
    }
}

private struct CycleCardMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cycle 02")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(AppColor.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Recovery Stack")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)

                HStack(spacing: 4) {
                    pill("BPC-157")
                    pill("TB-500")
                }

                progressBar
                    .padding(.top, 4)

                HStack {
                    Text("Day 14")
                    Spacer()
                    Text("of 84")
                }
                .font(.system(size: 7))
                .foregroundStyle(AppColor.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.surfaceSecondary.opacity(0.6))
    }

    private func pill(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 7, weight: .semibold))
            .foregroundStyle(AppColor.accentLight)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background {
                Capsule().fill(AppColor.accentPrimary.opacity(0.18))
            }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(AppColor.surfaceElevated)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [AppColor.accentPrimary, AppColor.accentLight],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * 0.16)
            }
        }
        .frame(height: 4)
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        PaywallPhoneMockupRow()
    }
    .preferredColorScheme(.dark)
}
