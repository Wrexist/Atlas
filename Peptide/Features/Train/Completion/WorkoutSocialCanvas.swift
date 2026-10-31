import SwiftUI
import UIKit

/// Fixed export composition. The preview and file use exactly this canvas;
/// native controls, private notes and precise timestamps never enter its tree.
struct WorkoutSocialCanvas: View {
    let summary: WorkoutRecapEngine.Summary
    let unit: MeasurementUnit
    let options: WorkoutShareOptions

    private var layout: ShareLayout { options.format.layout }
    private var compact: Bool { layout != .tall }

    var body: some View {
        Group {
            if layout == .wide {
                wideContent
            } else {
                ViewThatFits(in: .vertical) {
                    content(showsMap: true)
                    content(showsMap: false)
                }
            }
        }
        .padding(.horizontal, compact ? 24 : 28)
        .padding(.top, layout == .tall ? 48 : 24)
        .padding(.bottom, layout == .tall ? 64 : 24)
        .frame(width: options.format.logicalSize.width, height: options.format.logicalSize.height)
        .foregroundStyle(AppColor.textPrimary)
        .background(AppColor.background)
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .large)
    }

    private func content(showsMap: Bool) -> some View {
        VStack(spacing: compact ? 8 : 12) {
            header
            titleBlock
            metricsCard
            if showsMap {
                anatomy
                    .frame(height: compact ? 96 : 168)
            }
            muscleLines
            // Method notes live behind the recap's info buttons, not in the
            // exported image.
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Landscape: the anatomy map is the hero on the left, the same text
    /// blocks stack on the right.
    private var wideContent: some View {
        HStack(alignment: .center, spacing: 20) {
            anatomy
                .frame(width: 148)
                .frame(maxHeight: .infinity)
            VStack(spacing: 8) {
                header
                titleBlock
                metricsCard
                muscleLines
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image("AtlasLogo").resizable().scaledToFit().frame(width: 22, height: 22)
            Text("ATLAS").font(.subheadline.weight(.semibold)).tracking(3)
            Spacer()
            Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColor.positive)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(options.includeName ? summary.name : String(localized: "Workout"))
                .font(.title2.weight(.bold)).lineLimit(layout == .wide ? 1 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if options.includeDate, let date = summary.session.finishedAt {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    private var metricsCard: some View {
        HStack(alignment: .top, spacing: 12) {
            metric(summary.duration.label, label: "Duration")
            metric(summary.workingSetLabel, label: "Working sets")
            if options.includeVolume, let volume = summary.volumeKg {
                metric(RecapFormat.volume(volume, unit: unit), label: "Recorded volume")
            }
        }
        .padding(12)
        .background(AppColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 16))
    }

    private var anatomy: some View {
        RecapAnatomy(muscles: summary.muscles)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var muscleLines: some View {
        VStack(alignment: .leading, spacing: 5) {
            muscleLine(role: .primary, color: AppColor.trainingPrimaryMuscle)
            muscleLine(role: .supporting, color: AppColor.trainingSecondaryMuscle)
            if summary.muscles.isEmpty {
                Text("Muscle mapping unavailable").font(.caption)
            }
            if summary.missingMappings > 0 {
                Text("Some exercises have no muscle mapping").font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.headline).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            Text(label).font(.caption2).foregroundStyle(AppColor.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func muscleLine(role: WorkoutRecapEngine.Role, color: Color) -> some View {
        let names = summary.muscles.filter { $0.role == role }.map { $0.displayName }
        return Group {
            if !names.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(role.displayName).foregroundStyle(color).fontWeight(.semibold)
                    Text(names.joined(separator: ", ")).lineLimit(1)
                }.font(.caption)
            }
        }
    }
}

@MainActor
enum WorkoutSocialRenderer {
    static func image(summary: WorkoutRecapEngine.Summary, unit: MeasurementUnit,
                      options: WorkoutShareOptions) throws -> UIImage {
        let renderer = ImageRenderer(content: Group {
            if options.style == .highlight {
                WorkoutHighlightCanvas(summary: summary, unit: unit, options: options)
            } else {
                WorkoutSocialCanvas(summary: summary, unit: unit, options: options)
            }
        })
        renderer.scale = options.format.renderScale
        renderer.isOpaque = true
        guard let image = renderer.uiImage else { throw WorkoutMediaError.render }
        return image
    }
}
