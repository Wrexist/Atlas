import SwiftUI

/// Logs one manual body-fat, waist, blood-pressure or temperature reading
/// into Apple Health, where the Biology row reads it back. Health asks
/// for access the first time; a refusal says where to change it instead
/// of failing quietly.
struct BodyMeasurementEntrySheet: View {
    let biomarker: Biomarker
    let unit: MeasurementUnit
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var diastolicText = ""
    @State private var measuredAt = Date()
    @State private var isSaving = false
    @State private var saveFailed = false
    @FocusState private var isFieldFocused: Bool

    private var isBloodPressure: Bool { biomarker == .bloodPressure }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(biomarker.displayName)
                    .font(AppFont.title2)
                    .foregroundStyle(AppColor.textPrimary)
                Text("Saved to Apple Health")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                fields
                if let rangeHint {
                    Text(rangeHint)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.warning)
                }
                DatePicker("Measured", selection: $measuredAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }

            if saveFailed {
                Text("Atlas isn't allowed to write to Apple Health. Turn it on in Settings › Health › Data Access & Devices › Atlas.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GlassButton(title: "Save", icon: "checkmark", isFullWidth: true) {
                Task { await save() }
            }
            .disabled(!canSave || isSaving)
        }
        .padding(Spacing.screenPadding)
        .onAppear { isFieldFocused = true }
        .liquidGlassPresentation(detents: [.medium])
    }

    @ViewBuilder
    private var fields: some View {
        if isBloodPressure {
            HStack(spacing: Spacing.sm) {
                GlassTextField(placeholder: "Systolic", text: $text, icon: "arrow.up", focus: $isFieldFocused)
                    .keyboardType(.numberPad)
                GlassTextField(placeholder: "Diastolic", text: $diastolicText, icon: "arrow.down")
                    .keyboardType(.numberPad)
            }
        } else {
            GlassTextField(
                placeholder: "Value in \(biomarker.displayUnit(for: unit) ?? "")",
                text: $text,
                icon: biomarker.icon,
                focus: $isFieldFocused
            )
            .keyboardType(.decimalPad)
        }
    }

    private var bloodPressure: (systolic: Double, diastolic: Double)? {
        BodyMeasurementInput.bloodPressure(systolic: text, diastolic: diastolicText)
    }

    private var metricValue: Double? {
        BodyMeasurementInput.metricValue(text, for: biomarker, unit: unit)
    }

    private var canSave: Bool {
        isBloodPressure ? bloodPressure != nil : metricValue != nil
    }

    /// Says why Save is disabled once something has been typed.
    private var rangeHint: String? {
        if isBloodPressure {
            guard !text.isEmpty, !diastolicText.isEmpty, bloodPressure == nil else { return nil }
            return String(localized: "Enter systolic over diastolic, for example 120 over 80.")
        }
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, metricValue == nil,
              let range = BodyMeasurementInput.plausibleRange(for: biomarker)
        else { return nil }
        let low = displayLabel(range.lowerBound)
        let high = displayLabel(range.upperBound)
        return String(localized: "Enter a value between \(low) and \(high).")
    }

    private func displayLabel(_ metric: Double) -> String {
        BiomarkerSeriesService.formatValue(biomarker.displayValue(metric, for: unit), for: biomarker)
            + (biomarker.displayUnit(for: unit).map { " \($0)" } ?? "")
    }

    private func save() async {
        let health = HealthKitService.shared
        isSaving = true
        defer { isSaving = false }
        if !health.canWriteBodyMeasurement(biomarker) {
            _ = await health.requestBodyMeasurementAuthorization()
        }
        guard health.canWriteBodyMeasurement(biomarker) else {
            saveFailed = true
            Haptics.error()
            return
        }
        let saved: Bool
        if let reading = bloodPressure, isBloodPressure {
            saved = await health.writeBodyMeasurement(biomarker, value: reading.systolic, diastolic: reading.diastolic, date: measuredAt)
        } else if let metricValue {
            saved = await health.writeBodyMeasurement(biomarker, value: metricValue, date: measuredAt)
        } else {
            return
        }
        guard saved else {
            saveFailed = true
            Haptics.error()
            return
        }
        Haptics.success()
        onSaved()
        dismiss()
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        BodyMeasurementEntrySheet(biomarker: .bloodPressure, unit: .metric) {}
    }
}
