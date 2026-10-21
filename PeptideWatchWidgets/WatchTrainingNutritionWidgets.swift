import SwiftUI
import WidgetKit

/// The snapshot the Watch app mirrors into its App Group container, read
/// the same way the dose, score and vitals providers read it.
private enum WatchSnapshotFile {
    static func read() -> WatchData? {
        guard let url = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
                .appendingPathComponent("watch_data.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WatchData.self, from: data)
    }
}

// MARK: - Workout

struct WatchWorkoutEntry: TimelineEntry {
    let date: Date
    let workout: WatchWorkoutSnapshot?
    let training: WatchTrainingSnapshot?

    static let placeholder: WatchWorkoutEntry = {
        let bench = WatchWorkoutSnapshot.Exercise(
            id: UUID(), name: "Bench Press", restSeconds: 90,
            sets: (1...4).map { index in
                WatchWorkoutSnapshot.SetRow(
                    id: UUID(), index: index, weightKg: 80, reps: 8,
                    completed: index <= 2, isWarmup: false, logsReps: true
                )
            }
        )
        return WatchWorkoutEntry(
            date: .now,
            workout: WatchWorkoutSnapshot(
                sessionId: UUID(), name: "Push",
                timerStartedAt: .now.addingTimeInterval(-24 * 60),
                pausedElapsedSeconds: nil,
                exercises: [bench], selectedExerciseID: bench.id, rest: nil
            ),
            training: nil
        )
    }()
}

/// The workout in progress, or this week's training between workouts.
/// The Watch app reloads every timeline on each push from the phone, so
/// set changes arrive that way; the timeline only has to flip a rest into
/// "lifting" when its countdown runs out.
struct WatchWorkoutProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchWorkoutEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (WatchWorkoutEntry) -> Void) {
        completion(context.isPreview ? .placeholder : entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchWorkoutEntry>) -> Void) {
        let now = Date.now
        var entries = [entry(at: now)]
        if let workout = entries[0].workout, workout.isResting(at: now), let rest = workout.rest {
            entries.append(entry(at: rest.endsAt))
        }
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now
        completion(Timeline(entries: entries, policy: .after(next)))
    }

    private func entry(at date: Date) -> WatchWorkoutEntry {
        let data = WatchSnapshotFile.read()?.forDisplay(at: date)
        return WatchWorkoutEntry(date: date, workout: data?.workout, training: data?.training)
    }
}

struct WatchWorkoutEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchWorkoutEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryInline: inline
            default: rectangular
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var restInterval: ClosedRange<Date>? {
        guard let workout = entry.workout, workout.isResting(at: entry.date), let rest = workout.rest else { return nil }
        return rest.endsAt.addingTimeInterval(-max(rest.totalSeconds, 1))...rest.endsAt
    }

    // MARK: Circular

    @ViewBuilder
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let workout = entry.workout {
                Circle()
                    .trim(from: 0, to: max(0.001, setProgress(workout)))
                    .stroke(WatchPalette.training, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(3)
                if workout.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.title3)
                        .widgetAccentable()
                } else if let restInterval {
                    Text(timerInterval: restInterval, countsDown: true)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                        .widgetAccentable()
                } else {
                    VStack(spacing: -2) {
                        Text("\(workout.completedSets)")
                            .font(.title3.weight(.bold))
                            .widgetAccentable()
                        Text("/\(workout.totalSets)")
                            .font(.caption2)
                    }
                }
            } else {
                VStack(spacing: -1) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(WatchPalette.training)
                    Text("\(entry.training?.workoutsThisWeek ?? 0)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .widgetAccentable()
                    Text("WEEK")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    // MARK: Rectangular

    @ViewBuilder
    private var rectangular: some View {
        if let workout = entry.workout {
            VStack(alignment: .leading, spacing: 1) {
                Label(workout.name.isEmpty ? String(localized: "Workout") : workout.name,
                      systemImage: "figure.strengthtraining.traditional")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WatchPalette.training)
                    .lineLimit(1)
                Group {
                    if let paused = workout.pausedElapsedSeconds {
                        Text("Paused · \(Duration.seconds(paused).formatted(.time(pattern: .minuteSecond)))")
                    } else if let restInterval {
                        Text("Rest \(Text(timerInterval: restInterval, countsDown: true))")
                    } else {
                        Text(workout.timerStartedAt, style: .timer)
                    }
                }
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .widgetAccentable()
                Text(detail(workout))
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Label("Training", systemImage: "dumbbell.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WatchPalette.training)
                Text("\(entry.training?.workoutsThisWeek ?? 0) this week")
                    .font(.headline)
                    .widgetAccentable()
                Text(lastWorkoutLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Inline

    @ViewBuilder
    private var inline: some View {
        if let workout = entry.workout {
            Text("\(workout.completedSets)/\(workout.totalSets) sets · \(workout.name.isEmpty ? String(localized: "Workout") : workout.name)")
        } else {
            Text("\(entry.training?.workoutsThisWeek ?? 0) workouts this week")
        }
    }

    // MARK: Helpers

    private func setProgress(_ workout: WatchWorkoutSnapshot) -> Double {
        guard workout.totalSets > 0 else { return 0 }
        return min(1, Double(workout.completedSets) / Double(workout.totalSets))
    }

    /// "Bench Press · 5/12 sets": what's on the bar, then how far through.
    private func detail(_ workout: WatchWorkoutSnapshot) -> String {
        let sets = String(localized: "\(workout.completedSets)/\(workout.totalSets) sets")
        guard let exercise = workout.upNext?.exercise.name else { return sets }
        return "\(exercise) · \(sets)"
    }

    private var lastWorkoutLine: String {
        guard let last = entry.training?.lastWorkout else { return String(localized: "No workouts yet") }
        let day = last.finishedAt.formatted(.dateTime.weekday(.abbreviated))
        return last.name.isEmpty ? String(localized: "Last: \(day)") : "\(last.name) · \(day)"
    }

    private var spoken: String {
        guard let workout = entry.workout else {
            return String(localized: "\(entry.training?.workoutsThisWeek ?? 0) workouts this week")
        }
        if workout.isPaused { return String(localized: "Workout paused") }
        if restInterval != nil { return String(localized: "Resting, \(workout.completedSets) of \(workout.totalSets) sets done") }
        return String(localized: "\(workout.completedSets) of \(workout.totalSets) sets done")
    }
}

struct WatchWorkoutWidget: Widget {
    let kind = "WatchWorkoutWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchWorkoutProvider()) { entry in
            WatchWorkoutEntryView(entry: entry)
                .widgetURL(WatchPage.workout.url)
        }
        .configurationDisplayName("Workout")
        .description("Your workout in progress, or this week's training.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - Nutrition

struct WatchNutritionEntry: TimelineEntry {
    let date: Date
    let nutrition: WatchNutritionSnapshot?

    static let placeholder = WatchNutritionEntry(
        date: .now,
        nutrition: WatchNutritionSnapshot(
            caloriesToday: 1_480, calorieTarget: 2_200,
            proteinToday: 96, proteinTarget: 150,
            mealLoggingStreak: 6, mealEntriesToday: 3
        )
    )
}

/// Today's calories and protein. A snapshot from an earlier day reads as
/// an empty day, and a second entry at midnight empties a full one, so the
/// face never carries yesterday's totals into the morning.
struct WatchNutritionProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchNutritionEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (WatchNutritionEntry) -> Void) {
        completion(context.isPreview ? .placeholder : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchNutritionEntry>) -> Void) {
        let calendar = Calendar.current
        let current = currentEntry()
        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now)
        let reset = WatchNutritionEntry(date: midnight, nutrition: current.nutrition?.emptied)
        completion(Timeline(entries: [current, reset], policy: .atEnd))
    }

    private func currentEntry() -> WatchNutritionEntry {
        WatchNutritionEntry(date: .now, nutrition: WatchSnapshotFile.read()?.forDisplay(at: .now).nutrition)
    }
}

struct WatchNutritionEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchNutritionEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryInline: inline
            default: rectangular
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let nutrition = entry.nutrition {
                ring(nutrition.calorieProgress, color: WatchPalette.calories, inset: 3)
                ring(nutrition.proteinProgress, color: WatchPalette.protein, inset: 9)
                Text(nutrition.caloriesToday, format: .number.notation(.compactName))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 13)
                    .widgetAccentable()
            } else {
                Image(systemName: "fork.knife")
                    .font(.title3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func ring(_ progress: Double, color: Color, inset: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: max(0.001, progress))
            .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .padding(inset)
    }

    @ViewBuilder
    private var rectangular: some View {
        if let nutrition = entry.nutrition {
            VStack(alignment: .leading, spacing: 2) {
                macroRow(
                    symbol: "flame.fill",
                    value: nutrition.calorieTarget > 0
                        ? "\(nutrition.caloriesToday.formatted()) / \(nutrition.calorieTarget.formatted()) kcal"
                        : "\(nutrition.caloriesToday.formatted()) kcal",
                    progress: nutrition.calorieProgress,
                    color: WatchPalette.calories
                )
                macroRow(
                    symbol: "bolt.fill",
                    value: nutrition.proteinTarget > 0
                        ? "\(nutrition.proteinToday) / \(nutrition.proteinTarget) g"
                        : "\(nutrition.proteinToday) g",
                    progress: nutrition.proteinProgress,
                    color: WatchPalette.protein
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Label("Nutrition", systemImage: "fork.knife")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WatchPalette.calories)
                Text("Log a meal on iPhone")
                    .font(.headline)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func macroRow(symbol: String, value: String, progress: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(value, systemImage: symbol)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetAccentable()
            ProgressView(value: progress)
                .tint(color)
        }
    }

    @ViewBuilder
    private var inline: some View {
        if let nutrition = entry.nutrition {
            Text("\(nutrition.caloriesToday.formatted()) kcal · \(nutrition.proteinToday) g protein")
        } else {
            Text("Atlas Nutrition")
        }
    }

    private var spoken: String {
        guard let nutrition = entry.nutrition else { return String(localized: "No meals logged") }
        return String(localized: "\(nutrition.caloriesToday) calories, \(nutrition.proteinToday) grams protein")
    }
}

struct WatchNutritionWidget: Widget {
    let kind = "WatchNutritionWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchNutritionProvider()) { entry in
            WatchNutritionEntryView(entry: entry)
                .widgetURL(WatchPage.nutrition.url)
        }
        .configurationDisplayName("Calories & Protein")
        .description("Today's calories and protein against your targets.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
