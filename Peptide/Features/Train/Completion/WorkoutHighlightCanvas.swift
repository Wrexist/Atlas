import SwiftUI

/// Light illustration-led card based on the supplied completion reference.
/// All totals come from the same recap projection as the dark summary.
/// Portrait formats stack the blocks in one column; landscape keeps the
/// exercise and its illustration on the left and the totals on the right.
struct WorkoutHighlightCanvas: View {
    let summary: WorkoutRecapEngine.Summary
    let unit: MeasurementUnit
    let options: WorkoutShareOptions

    private var entry: WorkoutRecapEngine.Entry? {
        summary.entries.first { $0.id == options.featuredEntryID } ?? summary.entries.first
    }
    private var layout: ShareLayout { options.format.layout }
    private var compact: Bool { layout != .tall }
    private var verticalInsets: (top: CGFloat, bottom: CGFloat) {
        switch layout {
        case .tall: (top: 44, bottom: 64)
        case .compact: (top: 20, bottom: 20)
        case .wide: (top: 16, bottom: 16)
        }
    }

    var body: some View {
        content
            .padding(compact ? 16 : 20)
            .background(AppColor.trainingBackground, in: RoundedRectangle(cornerRadius: 28))
            .padding(.horizontal, 20)
            .padding(.top, verticalInsets.top)
            .padding(.bottom, verticalInsets.bottom)
            .frame(width: options.format.logicalSize.width, height: options.format.logicalSize.height)
            .foregroundStyle(AppColor.recapText)
            .background(AppColor.recapBackground)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large)
    }

    @ViewBuilder
    private var content: some View {
        if layout == .wide {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    entryCard
                    hero
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Spacer(minLength: 0)
                    headline
                    metricsRow
                    Divider()
                    footer
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: compact ? 10 : 14) {
                entryCard
                hero
                headline
                metricsRow
                Divider()
                footer
            }
        }
    }

    @ViewBuilder
    private var entryCard: some View {
        if let entry {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(.subheadline.weight(.semibold)).lineLimit(compact ? 1 : 2)
                if let set = entry.sets.last {
                    Text("Logged set · \(RecapFormat.set(set, unit: unit))")
                        .font(.caption).foregroundStyle(AppColor.recapSecondary)
                        .lineLimit(layout == .wide ? 1 : 2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.recapCard, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 8) {
            ExerciseHeroView(exercise: entry.flatMap { ExerciseLibrary.shared.lookup(id: $0.exerciseID) }, interactive: false)
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
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(options.includeVolume && summary.volumeKg != nil ? "Recorded volume" : "Working sets")
                .font(.caption).foregroundStyle(AppColor.recapSecondary)
            Text(options.includeVolume && summary.volumeKg != nil
                 ? RecapFormat.volume(summary.volumeKg, unit: unit) : summary.workingSetLabel)
                .font(compact ? .title2.weight(.bold) : .largeTitle.weight(.bold)).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var metricsRow: some View {
        HStack(spacing: 12) {
            Label(summary.duration.label, systemImage: "clock")
            if summary.entries.isEmpty {
                Text("Exercises not logged")
            } else {
                Text("^[\(summary.entries.count) exercise](inflect: true)")
            }
            if options.includeVolume && summary.volumeKg != nil {
                Text("^[\(summary.workingSetCount) set](inflect: true)")
            }
        }
        .font(.caption).monospacedDigit()
        // The landscape column is narrow; shrink before wrapping there.
        .lineLimit(layout == .wide ? 1 : nil)
        .minimumScaleFactor(layout == .wide ? 0.8 : 1)
    }

    private var footer: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(options.includeName ? summary.name : String(localized: "Workout"))
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
}
