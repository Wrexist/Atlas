import SwiftUI

/// A bare barcode viewfinder for the fridge: one read hands the code back
/// and closes. Devices that can't run the scanner type the code instead.
struct FridgeBarcodeSheet: View {
    let onCode: (String) -> Void
    let onClose: () -> Void

    @State private var typed = ""
    @State private var errorText: String?
    @State private var isDone = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top) {
                Text("Scan the barcode")
                    .font(AppFont.title2)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: 0)
                GlassIconButton(icon: "xmark", accessibilityLabel: "Close", size: 32, action: onClose)
            }
            if BarcodeScannerView.canScan && errorText == nil {
                BarcodeScannerView(onDetected: detected, onError: { errorText = $0 })
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
                Text("Hold the code inside the frame. Exact product data comes from Open Food Facts.")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                manualEntry
                Spacer(minLength: 0)
            }
        }
        .padding(Spacing.xl)
        .background(AppColor.background)
    }

    private var manualEntry: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let errorText {
                Text(errorText)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }
            GlassTextField(placeholder: "Barcode digits", text: $typed, icon: "barcode", label: "Barcode")
                .keyboardType(.numberPad)
            GlassButton(title: "Look up", icon: "magnifyingglass", style: .primary, isFullWidth: true) {
                detected(typed)
            }
            .disabled(typed.filter(\.isNumber).count < 8)
        }
    }

    private func detected(_ code: String) {
        guard !isDone else { return }
        isDone = true
        Haptics.success()
        onCode(code.filter(\.isNumber))
    }
}
