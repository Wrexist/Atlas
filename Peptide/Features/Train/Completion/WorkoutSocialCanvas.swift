import SwiftUI
import UIKit

/// Fixed export composition. The preview and file use exactly this canvas;
/// native controls, private notes and precise timestamps never enter its tree.
struct WorkoutSocialCanvas: View {
    let summary: WorkoutRecapEngine.Summary
    let unit: MeasurementUnit
    let options: WorkoutShareOptions

    private var compact: Bool { options.format == .post }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(showsMap: true)
            content(showsMap: false)
        }
        .padding(.horizontal, compact ? 24 : 28)
        .padding(.top, compact ? 24 : 48)
        .padding(.bottom, compact ? 24 : 64)
        .frame(width: options.format.logicalSize.width, height: options.format.logicalSize.height)
        .foregroundStyle(AppColor.recapText)
        .background(AppColor.recapBackground)
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .large)
    }

    private func content(showsMap: Bool) -> some View {
        VStack(spacing: compact ? 8 : 12) {
            HStack(spacing: 8) {
                Image("AtlasLogo").resizable().scaledToFit().frame(width: 22, height: 22)
                Text("ATLAS").font(.subheadline.weight(.semibold)).tracking(3)
                Spacer()
                Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColor.recapSuccess)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(options.includeName ? summary.name : "Workout")
                    .font(.title2.weight(.bold)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if options.includeDate, let date = summary.session.finishedAt {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundStyle(AppColor.recapSecondary)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                metric(summary.duration.label, label: "Duration")
                metric(summary.workingSetLabel, label: "Working sets")
                if options.includeVolume, let volume = summary.volumeKg {
                    metric(RecapFormat.volume(volume, unit: unit), label: "Recorded volume")
                }
            }
            .padding(12)
            .background(AppColor.recapCard, in: RoundedRectangle(cornerRadius: 16))

            if showsMap {
              RecapAnatomy(muscles: summary.muscles)
                .frame(height: compact ? 96 : 168)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            }

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

            VStack(spacing: 3) {
                Text("Muscle focus estimated from logged exercises")
                if options.includeVolume && summary.volumeKg != nil && summary.excludedVolumeSets > 0 {
                    Text("Volume includes supported external-load sets only")
                }
            }
            .font(.caption2).foregroundStyle(AppColor.recapSecondary)
            .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.headline).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            Text(label).font(.caption2).foregroundStyle(AppColor.recapSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func muscleLine(role: WorkoutRecapEngine.Role, color: Color) -> some View {
        let names = summary.muscles.filter { $0.role == role }.map { $0.name.capitalized }
        return Group {
            if !names.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(role.rawValue).foregroundStyle(color).fontWeight(.semibold)
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
        renderer.scale = 3
        renderer.isOpaque = true
        guard let image = renderer.uiImage else { throw WorkoutMediaError.render }
        return image
    }
}
