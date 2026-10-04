import SwiftUI
import UIKit

struct WorkoutShareView: View {
    let summary: WorkoutRecapEngine.Summary
    let unit: MeasurementUnit
    @Environment(\.dismiss) private var dismiss
    @State private var includeName = true
    @State private var includeDate = false
    @State private var exportItem: WorkoutShareExport?
    @State private var exporting = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    WorkoutShareCard(summary: summary, unit: unit, includeName: includeName, includeDate: includeDate)
                        .environment(\.colorScheme, .dark)
                    Toggle("Include workout name", isOn: $includeName)
                    Toggle("Include date", isOn: $includeDate)
                    Text("Only this card is shared. Private notes, account details and exact times are excluded.")
                        .font(AppFont.subheadline).foregroundStyle(AppColor.recapSecondary)
                    if let error { Text(error).font(AppFont.subheadline).accessibilityIdentifier("workout-share-error") }
                    RecapAction(title: exporting ? "Preparing image…" : "Share") { export() }.disabled(exporting)
                }.padding(Spacing.screenPadding)
            }
            .recapScreen(title: "Share workout")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.minimumHitArea() } }
            .sheet(item: $exportItem) { item in
                    ShareSheet(activityItems: [item.image]) { shareError in
                        if shareError != nil {
                            error = "Sharing did not finish. Your saved workout is unchanged. Try again."
                        }
                    }
            }
        }
    }

    private func export() {
        guard !exporting else { return }
        exporting = true
        error = nil
        let nameIncluded = includeName
        let dateIncluded = includeDate
        Task { @MainActor in
            await Task.yield()
            let renderer = ImageRenderer(content:
                WorkoutShareCard(summary: summary, unit: unit, includeName: nameIncluded, includeDate: dateIncluded)
                    .frame(width: 390).padding(20).background(AppColor.recapBackground)
                    .environment(\.colorScheme, .dark).environment(\.dynamicTypeSize, .large))
            renderer.scale = 3
            if let image = renderer.uiImage { exportItem = WorkoutShareExport(image: image) }
            else { error = "Could not create the share image. Your saved workout is unchanged. Try again." }
            exporting = false
        }
    }
}

private struct WorkoutShareExport: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct WorkoutShareCard: View {
    let summary: WorkoutRecapEngine.Summary
    let unit: MeasurementUnit
    let includeName: Bool
    let includeDate: Bool
    var body: some View {
        RecapCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text(includeName ? summary.name : "Workout").font(AppFont.title2)
                if includeDate, let date = summary.session.finishedAt {
                    Text(date.formatted(date: .abbreviated, time: .omitted)).font(AppFont.subheadline)
                }
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Duration · \(summary.duration.label)")
                    Text("Working sets · \(summary.workingSetLabel)")
                    if let volume = summary.volumeKg {
                        Text("Recorded volume · \(RecapFormat.volume(volume, unit: unit))")
                    }
                }.font(AppFont.subheadline).monospacedDigit()
                if summary.excludedVolumeSets > 0 {
                    Text("Volume covers supported external-load repetition sets only.").font(AppFont.subheadline)
                }
                RecapAnatomy(muscles: summary.muscles).frame(maxWidth: 260).frame(maxWidth: .infinity)
                RecapMuscleNames(muscles: summary.muscles)
                Text("Estimated from logged exercises").font(AppFont.subheadline).foregroundStyle(AppColor.recapSecondary)
                RecapMissingMapping(count: summary.missingMappings)
                HStack(spacing: Spacing.sm) {
                    Image("AtlasLogo").resizable().scaledToFit().frame(width: 24, height: 24)
                    Text("ATLAS").font(AppFont.headline).tracking(3)
                }.frame(maxWidth: .infinity)
            }.foregroundStyle(AppColor.recapText)
        }
    }
}
