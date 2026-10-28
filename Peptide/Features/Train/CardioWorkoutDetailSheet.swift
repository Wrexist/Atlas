import SwiftUI

/// What a workout from Apple Health recorded. Read-only: Health owns it,
/// so editing happens there.
struct CardioWorkoutDetailSheet: View {
    let workout: ImportedCardioWorkout
    let unit: MeasurementUnit
    @Environment(\.dismiss) private var dismiss

    private struct Stat {
        let label: String
        let value: String
    }

    private var stats: [Stat] {
        [
            Stat(label: String(localized: "Duration"), value: CardioWorkoutEngine.durationLabel(workout.duration)),
            CardioWorkoutEngine.distanceLabel(meters: workout.distanceMeters, unit: unit)
                .map { Stat(label: String(localized: "Distance"), value: $0) },
            CardioWorkoutEngine.energyLabel(workout.activeKilocalories)
                .map { Stat(label: String(localized: "Active energy"), value: $0) },
            CardioWorkoutEngine.heartRateLabel(workout.averageHeartRate)
                .map { Stat(label: String(localized: "Avg heart rate"), value: $0) },
        ]
        .compactMap { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: Spacing.md), GridItem(.flexible())],
                        spacing: Spacing.md
                    ) {
                        ForEach(stats, id: \.label) { stat($0) }
                    }
                    Text("Edit or delete this workout in the Health app.")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .padding(Spacing.screenPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle(workout.activity.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.accentPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: workout.activity.symbol)
                .font(AppFont.scaled(28, weight: .semibold, relativeTo: .title1))
                .foregroundStyle(AppColor.accentPrimary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text((workout.start..<workout.end).formatted(.interval.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                if !workout.sourceName.isEmpty {
                    Text("Recorded by \(workout.sourceName)")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func stat(_ stat: Stat) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(stat.value)
                .font(AppFont.scaled(20, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
            Text(stat.label)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .glassSurface(cornerRadius: Spacing.smallCornerRadius)
        .accessibilityElement(children: .combine)
    }
}
