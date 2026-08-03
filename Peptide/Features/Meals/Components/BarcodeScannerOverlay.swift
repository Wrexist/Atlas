import SwiftUI

/// Decorative + interactive overlay layered above `BarcodeScannerView`'s
/// camera preview. Owns the reticle (with a subtle breathing animation
/// so the scanner feels "alive"), the torch toggle, and the bottom-of-
/// frame caption. Split out of `BarcodeScanFlow` so the flow file
/// stays focused on the state machine.
struct BarcodeScannerOverlay: View {
    @Binding var torchOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            reticle

            VStack {
                HStack {
                    Spacer()
                    if BarcodeTorch.isAvailable {
                        torchButton
                            .padding(Spacing.md)
                    }
                }
                Spacer()
            }
        }
        .onAppear {
            // Start the idle breathing animation once the overlay is
            // on screen. The animation drives a 6 % scale oscillation —
            // visible enough to feel alive, restrained enough not to
            // distract from a real barcode in frame.
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }

    private var reticle: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(AppColor.accentLight.opacity(0.85), lineWidth: 2)
            .frame(width: 240, height: 140)
            .scaleEffect(isBreathing ? 1.06 : 1.0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var torchButton: some View {
        Button {
            torchOn.toggle()
            BarcodeTorch.set(torchOn)
            BarcodeHaptics.detected()
        } label: {
            Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(torchOn ? AppColor.accentLight : .white)
                .frame(width: 44, height: 44)
                .glassControl(
                    .circle,
                    tint: torchOn ? AppColor.accentPrimary.opacity(0.18) : nil,
                    border: torchOn ? AppColor.accentPrimary.opacity(0.55) : AppColor.glassBorder
                )
        }
        .accessibilityLabel(torchOn ? "Turn off flashlight" : "Turn on flashlight")
        .accessibilityAddTraits(torchOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// Skeleton placeholder shown during the OFF lookup round-trip.
/// Replaces a generic spinner with a card-shaped shimmer so the
/// review-card destination feels prefigured — reduces perceived
/// latency without inventing a fake progress bar.
struct BarcodeLookupSkeleton: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            GlassCard(tinted: true) {
                HStack(spacing: Spacing.md) {
                    Circle()
                        .fill(AppColor.surfaceSecondary.opacity(0.8))
                        .frame(width: 56, height: 56)
                        .shimmer()

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColor.surfaceSecondary.opacity(0.8))
                            .frame(width: 160, height: 16)
                            .shimmer()
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColor.surfaceSecondary.opacity(0.8))
                            .frame(width: 100, height: 12)
                            .shimmer()
                    }
                    Spacer(minLength: 0)
                }
            }

            GlassCard(tinted: true) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(0..<4, id: \.self) { _ in
                        HStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppColor.surfaceSecondary.opacity(0.8))
                                .frame(width: 70, height: 12)
                                .shimmer()
                            Spacer()
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppColor.surfaceSecondary.opacity(0.8))
                                .frame(width: 60, height: 12)
                                .shimmer()
                        }
                    }
                }
            }

            Text("Looking up the product…")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
    }
}
