import SwiftUI

/// Light illustration-led card based on the supplied completion reference.
/// All totals come from the same recap projection as the dark summary.
struct WorkoutHighlightCanvas: View {
    let summary: WorkoutRecapEngine.Summary
    let unit: MeasurementUnit
    let options: WorkoutShareOptions

    private var entry: WorkoutRecapEngine.Entry? {
        summary.entries.first { $0.id == options.featuredEntryID } ?? summary.entries.first
    }
    private var compact: Bool { options.format == .post }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            if let entry {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name).font(.subheadline.weight(.semibold)).lineLimit(compact ? 1 : 2)
                    if let set = entry.sets.last {
                        Text("Logged set · \(RecapFormat.set(set, unit: unit))")
                            .font(.caption).foregroundStyle(AppColor.recapSecondary)
                            .lineLimit(2)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColor.recapCard, in: RoundedRectangle(cornerRadius: 16))
            }

            HStack(alignment: .top, spacing: 8) {
                ExerciseHeroView(exercise: entry.flatMap { ExerciseLibrary.shared.lookup(id: $0.exerciseID) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !compact && summary.entries.count > 1 {
                    VStack(spacing: 8) {
                        ForEach(Array(summary.entries.prefix(4))) { item in
                            ExerciseImageView(exercise: ExerciseLibrary.shared.lookup(id: item.exerciseID))
                                .frame(width: 34, height: 34)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(item.id == entry?.id ? AppColor.trainingSelection : .clear, lineWidth: 2))
                        }
                    }
                }
            }
            .frame(minHeight: compact ? 64 : 120, maxHeight: .infinity)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(options.includeVolume && summary.volumeKg != nil ? "Recorded volume" : "Working sets")
                    .font(.caption).foregroundStyle(AppColor.recapSecondary)
                Text(options.includeVolume && summary.volumeKg != nil
                     ? RecapFormat.volume(summary.volumeKg, unit: unit) : summary.workingSetLabel)
                    .font(compact ? .title2.weight(.bold) : .largeTitle.weight(.bold)).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Label(summary.duration.label, systemImage: "clock")
                Text(summary.entries.isEmpty ? "Exercises not logged" : "\(summary.entries.count) exercises")
                if options.includeVolume && summary.volumeKg != nil {
                    Text("\(summary.workingSetLabel) sets")
                }
            }
            .font(.caption).monospacedDigit()
            if options.includeVolume && summary.volumeKg != nil && summary.excludedVolumeSets > 0 {
                Text("Supported external-load sets only").font(.caption2)
                    .foregroundStyle(AppColor.recapSecondary)
            }
            Divider()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(options.includeName ? summary.name : "Workout")
                        .font(.subheadline.weight(.semibold)).lineLimit(compact ? 1 : 2)
                    if options.includeDate, let date = summary.session.finishedAt {
                        Text(date.formatted(date: .abbreviated, time: .omitted)).font(.caption2)
                    }
                }
                Spacer(minLength: 8)
                Image("AtlasLogo").resizable().scaledToFit().frame(width: 18, height: 18)
                Text("ATLAS").font(.caption2.weight(.semibold))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(compact ? 16 : 20)
        .background(AppColor.trainingBackground, in: RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 20)
        .padding(.top, compact ? 20 : 44)
        .padding(.bottom, compact ? 20 : 64)
        .frame(width: options.format.logicalSize.width, height: options.format.logicalSize.height)
        .foregroundStyle(AppColor.recapText)
        .background(AppColor.recapBackground)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .large)
    }
}
