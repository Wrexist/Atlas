import SwiftUI

/// Trio of stylised iPhone frames sitting under the paywall hero. Centre
/// frame stands upright, outer two tilt 8° outward to give a fanned
/// silhouette. Each frame renders a representative slice of the app
/// (workout log, meal scan, recovery ring) using SwiftUI primitives
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
    /// (`paywall-workout`, `paywall-meal`, `paywall-recovery`).
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
            case .mealScan: "paywall-meal"
            case .recovery: "paywall-recovery"
            }
        }
    }
}

// MARK: - Stylised in-frame content

private struct WorkoutMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Push Day")
                .font(AppFont.scaled(8, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(AppColor.textSecondary)

            mockSetRow(label: "Bench Press", detail: "3 × 8 · 80 kg", done: true)
            mockSetRow(label: "Overhead Press", detail: "3 × 10 · 45 kg", done: true)
            mockSetRow(label: "Dips", detail: "3 × 12", done: false)

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

    private func mockSetRow(label: LocalizedStringKey, detail: String, done: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(done ? AppColor.accentPrimary : AppColor.textTertiary)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(AppFont.scaled(8, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text(detail)
                    .font(AppFont.scaled(8))
                    .foregroundStyle(AppColor.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: Spacing.iconCornerRadius, style: .continuous)
                .fill(AppColor.surfaceElevated)
        }
    }
}

private struct MealScanMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Meal scan")
                .font(AppFont.scaled(8, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(AppColor.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Chicken rice bowl")
                    .font(AppFont.scaled(11, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)

                Text("640 kcal")
                    .font(AppFont.scaled(8, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)

                macroBar("Protein", fraction: 0.7, color: AppColor.macroProtein)
                macroBar("Carbs", fraction: 0.55, color: AppColor.macroCarbs)
                macroBar("Fat", fraction: 0.3, color: AppColor.macroFat)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.surfaceSecondary.opacity(0.6))
    }

    private func macroBar(_ label: LocalizedStringKey, fraction: CGFloat, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppFont.scaled(8))
                .foregroundStyle(AppColor.textTertiary)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColor.surfaceElevated)
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 4)
        }
    }
}

private struct RecoveryMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recovery")
                .font(AppFont.scaled(8, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(AppColor.textSecondary)

            ZStack {
                Circle()
                    .stroke(AppColor.surfaceElevated, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: 0.82)
                    .stroke(
                        AppColor.accentPrimary,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("82")
                    .font(AppFont.scaled(16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
            }
            .frame(width: 64, height: 64)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 2) {
                statRow("HRV", value: "64 ms")
                statRow("Sleep", value: "7h 42m")
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.surfaceSecondary.opacity(0.6))
    }

    private func statRow(_ label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(AppColor.textTertiary)
            Spacer()
            Text(value)
                .foregroundStyle(AppColor.textPrimary)
        }
        .font(AppFont.scaled(8, weight: .semibold))
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        PaywallPhoneMockupRow()
    }
    .preferredColorScheme(.dark)
}
