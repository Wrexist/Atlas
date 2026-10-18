import SwiftUI

/// Trio of stylised iPhone frames sitting under the paywall hero. Centre
/// frame stands upright, outer two tilt 8° outward to give a fanned
/// silhouette. Each frame renders a representative slice of the app
/// (workout progression, meal scan, recovery ring) using SwiftUI primitives
/// — dropping in actual screenshots is a follow-up that needs a snapshot
/// pipeline and the asset slots wired into the catalog.
struct PaywallPhoneMockupRow: View {
    var body: some View {
        HStack(spacing: -28) {
            phoneFrame(.workout)
                .scaleEffect(0.86)
                .rotationEffect(.degrees(-8))
                .offset(y: 12)
                .zIndex(1)

            phoneFrame(.mealScan)
                .scaleEffect(0.96)
                .zIndex(3)

            phoneFrame(.recovery)
                .scaleEffect(0.86)
                .rotationEffect(.degrees(8))
                .offset(y: 12)
                .zIndex(2)
        }
        .frame(height: 230)
        // Decorative artwork — the feature list below says the same in words.
        .accessibilityHidden(true)
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
    /// (`paywall-workout`, `paywall-mealscan`, `paywall-recovery`).
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
            case .workout:  WorkoutMock()
            case .mealScan: MealScanMock()
            case .recovery: RecoveryMock()
            }
        }
    }

    private enum MockupKind {
        case workout, mealScan, recovery

        /// Asset-catalog name the mockup row tries to load before
        /// falling back to the SwiftUI mock. Keep these stable —
        /// the snapshot pipeline writes PNGs under these exact names.
        var assetName: String {
            switch self {
            case .workout:  "paywall-workout"
            case .mealScan: "paywall-mealscan"
            case .recovery: "paywall-recovery"
            }
        }
    }
}

// MARK: - Stylised in-frame content

private struct MockEyebrow: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(AppFont.scaled(8, weight: .heavy))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(AppColor.textSecondary)
    }
}

/// Weekly top set climbing — the training progression chart in miniature.
private struct WorkoutMock: View {
    private let weeklyLoads: [CGFloat] = [0.45, 0.55, 0.6, 0.72, 0.85]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MockEyebrow(text: "Progress")

            Text("Bench Press")
                .font(AppFont.scaled(11, weight: .bold))
                .foregroundStyle(AppColor.textPrimary)

            Text("+7.5 kg in 5 weeks")
                .font(AppFont.scaled(8, weight: .semibold))
                .foregroundStyle(AppColor.positive)

            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(weeklyLoads.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == weeklyLoads.count - 1 ? AppColor.accentPrimary : AppColor.accentPrimary.opacity(0.35))
                            .frame(height: proxy.size.height * weeklyLoads[index])
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }

            HStack {
                Text("W1")
                Spacer()
                Text("W5")
            }
            .font(AppFont.scaled(8))
            .foregroundStyle(AppColor.textTertiary)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.surfaceSecondary.opacity(0.6))
    }
}

/// A scanned plate resolved into calories and macros.
private struct MealScanMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MockEyebrow(text: "Meal scan")

            RoundedRectangle(cornerRadius: Spacing.iconCornerRadius, style: .continuous)
                .fill(AppColor.surfaceElevated)
                .frame(height: 56)
                .overlay {
                    Image(systemName: "camera.viewfinder")
                        .font(AppFont.scaled(20, weight: .light))
                        .foregroundStyle(AppColor.accentLight)
                }

            Text("Chicken rice bowl")
                .font(AppFont.scaled(8, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)

            Text("540 kcal")
                .font(AppFont.scaled(11, weight: .bold))
                .foregroundStyle(AppColor.textPrimary)

            macroRow(label: "P", fraction: 0.7, color: AppColor.macroProtein)
            macroRow(label: "C", fraction: 0.55, color: AppColor.macroCarbs)
            macroRow(label: "F", fraction: 0.3, color: AppColor.macroFat)

            Spacer(minLength: 0)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.surfaceSecondary.opacity(0.6))
    }

    private func macroRow(label: LocalizedStringKey, fraction: CGFloat, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(AppFont.scaled(8, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 8, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColor.surfaceElevated)
                    Capsule().fill(color).frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 4)
        }
    }
}

/// The morning recovery score with the two signals behind it.
private struct RecoveryMock: View {
    private let score: CGFloat = 0.82

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MockEyebrow(text: "Recovery")

            ZStack {
                Circle()
                    .stroke(AppColor.surfaceElevated, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: score)
                    .stroke(AppColor.positive, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("82")
                    .font(AppFont.scaled(16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
            }
            .frame(width: 64, height: 64)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            signalRow(icon: "waveform.path.ecg", label: "HRV", value: "64 ms", color: AppColor.metricHRV)
            signalRow(icon: "moon.fill", label: "Sleep", value: "7h 40m", color: AppColor.metricSleep)

            Spacer(minLength: 0)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.surfaceSecondary.opacity(0.6))
    }

    private func signalRow(icon: String, label: LocalizedStringKey, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(AppFont.scaled(8, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(AppFont.scaled(8, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
            Spacer(minLength: 0)
            Text(value)
                .font(AppFont.scaled(8, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: Spacing.iconCornerRadius, style: .continuous)
                .fill(AppColor.surfaceElevated)
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        PaywallPhoneMockupRow()
    }
    .preferredColorScheme(.dark)
}
