import Foundation

/// Deterministic demo state for App Store screenshots. Every value
/// here is hand-tuned to make a single tab read as "successful
/// long-running user" — high compliance (~91 %), 14-day streak,
/// outcome check-ins on a gradual upward trend, an HRV uptrend,
/// a fresh AI weekly recap, several lab draws, and a believable
/// food log.
///
/// Build it lazily via `ScreenshotSeedData.build()` so the
/// reference dates are computed against `Date()` at activation
/// time — that way the heatmap, weekly summary, and "today's
/// schedule" surfaces all line up with the simulator's current
/// clock, not a baked-in calendar moment.
///
/// Deterministic with respect to current date: re-activating
/// screenshot mode at the same wall-clock produces an identical
/// seed, so the user can capture, retake, and re-capture without
/// the demo drifting underneath them.
enum ScreenshotSeedData {

    struct Seed {
        let profile: UserProfile
        let protocols: [PeptideProtocol]
        let entries: [ProtocolEntry]
    }

    static func build(referenceDate: Date = Date()) -> Seed {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2 // Monday

        let protocols = buildProtocols(referenceDate: referenceDate)
        let entries = buildEntries(
            protocols: protocols,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let profile = buildProfile(
            referenceDate: referenceDate,
            calendar: calendar,
            entries: entries
        )

        return Seed(profile: profile, protocols: protocols, entries: entries)
    }

    // MARK: - Protocols

    /// Four active stacks with deliberate variety in cadence
    /// (daily, 5x weekly, 2x weekly, weekly) so the Today schedule
    /// + the calendar heatmap both render with rich texture.
    private static func buildProtocols(referenceDate: Date) -> [PeptideProtocol] {
        let calendar = Calendar.current
        let monthAgo = calendar.date(byAdding: .day, value: -28, to: referenceDate) ?? referenceDate
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: referenceDate) ?? referenceDate
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: referenceDate) ?? referenceDate

        return [
            PeptideProtocol(
                id: UUID(),
                name: "Recovery Stack",
                peptides: [MockPeptides.bpc157, MockPeptides.tb500],
                schedule: ProtocolSchedule(
                    daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
                    timesPerDay: 1,
                    preferredTimes: ["08:00"]
                ),
                cycleLengthWeeks: 6,
                startDate: monthAgo,
                status: .active,
                notes: "Morning subQ — pre-training."
            ),
            PeptideProtocol(
                id: UUID(),
                name: "HGH Axis",
                peptides: [MockPeptides.cjc1295, MockPeptides.igf1lr3],
                schedule: ProtocolSchedule(
                    daysOfWeek: [1, 2, 3, 4, 5],
                    timesPerDay: 1,
                    preferredTimes: ["22:00"]
                ),
                cycleLengthWeeks: 8,
                startDate: twoWeeksAgo,
                status: .active,
                notes: "Pre-bed, fasted."
            ),
            PeptideProtocol(
                id: UUID(),
                name: "Cognitive",
                peptides: [MockPeptides.selank],
                schedule: ProtocolSchedule(
                    daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
                    timesPerDay: 2,
                    preferredTimes: ["09:00", "14:00"]
                ),
                cycleLengthWeeks: 4,
                startDate: weekAgo,
                status: .active,
                notes: "Intranasal — 2× daily, focus blocks."
            ),
            PeptideProtocol(
                id: UUID(),
                name: "Longevity",
                peptides: [MockPeptides.epitalon, MockPeptides.ghkCu],
                schedule: ProtocolSchedule(
                    daysOfWeek: [1],
                    timesPerDay: 1,
                    preferredTimes: ["08:00"]
                ),
                cycleLengthWeeks: 12,
                startDate: monthAgo,
                status: .active,
                notes: "Monday morning — 10-day cycles."
            ),
        ]
    }

    // MARK: - Entries

    /// 30 days of entries with ~91 % compliance and a clean
    /// 14-day streak. Today gets one logged + one pending so the
    /// Today Overview Card reads as "halfway through the day,
    /// in flow".
    private static func buildEntries(
        protocols: [PeptideProtocol],
        referenceDate: Date,
        calendar: Calendar
    ) -> [ProtocolEntry] {
        var entries: [ProtocolEntry] = []
        let stdCalendar = Calendar.current

        for dayOffset in (0..<30).reversed() {
            guard let day = stdCalendar.date(byAdding: .day, value: -dayOffset, to: referenceDate)
            else { continue }
            for proto in protocols where proto.schedule.isActive(on: day) {
                guard let firstPeptide = proto.peptides.first else { continue }
                for (slotIndex, time) in proto.schedule.preferredTimes.enumerated() {
                    let entryTime = scheduledDate(for: day, time: time)
                        ?? day.addingTimeInterval(TimeInterval(8 + slotIndex) * 3600)
                    let isToday = stdCalendar.isDate(entryTime, inSameDayAs: referenceDate)
                    // Today's later slots stay pending so the Today
                    // hero can render a "1 of 2 logged" state.
                    let completed: Bool
                    if isToday {
                        completed = slotIndex == 0 && entryTime <= referenceDate
                    } else {
                        // 91 % overall compliance — fake one missed
                        // dose every ~12 entries using a stable
                        // deterministic skip pattern.
                        completed = ((dayOffset + slotIndex) % 12) != 7
                    }
                    let dose = proto.peptides.first?.dosageRange.components(separatedBy: "-").first ?? "250 mcg"
                    entries.append(
                        ProtocolEntry(
                            id: UUID(),
                            protocolId: proto.id,
                            peptide: firstPeptide,
                            date: entryTime,
                            dose: dose.trimmingCharacters(in: .whitespaces),
                            notes: "",
                            completed: completed,
                            actualDose: completed ? dose.trimmingCharacters(in: .whitespaces) : nil,
                            actualTime: completed ? entryTime : nil,
                            injectionSite: completed ? "Left Abdomen" : nil
                        )
                    )
                }
            }
        }
        return entries
    }

    private static func scheduledDate(for day: Date, time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let parsed = formatter.date(from: time) else { return nil }
        let components = Calendar.current.dateComponents([.hour, .minute], from: parsed)
        return Calendar.current.date(
            bySettingHour: components.hour ?? 8,
            minute: components.minute ?? 0,
            second: 0,
            of: day
        )
    }

    // MARK: - Profile

    private static func buildProfile(
        referenceDate: Date,
        calendar: Calendar,
        entries: [ProtocolEntry]
    ) -> UserProfile {
        var profile = UserProfile(
            name: "Alex",
            goals: ["Recovery", "Better Sleep", "Cognitive Edge", "Anti-Aging"],
            memberSince: Calendar.current.date(byAdding: .month, value: -6, to: referenceDate) ?? referenceDate,
            healthConnected: true,
            hapticFeedbackEnabled: true,
            doseRemindersEnabled: true,
            biometricLockEnabled: false,
            bodyMetrics: BodyMetrics(
                weightKg: 78.4,
                heightCm: 180,
                age: 30,
                sex: .male,
                activityLevel: .active,
                unit: .imperial
            ),
            nutritionTargets: NutritionTargets(
                calories: 2400,
                proteinG: 180,
                carbsG: 240,
                fatG: 80,
                fiberG: 30
            ),
            weightHistory: buildWeightHistory(referenceDate: referenceDate),
            dailyConsumption: buildConsumption(referenceDate: referenceDate),
            workoutHistory: buildWorkouts(referenceDate: referenceDate),
            bio: "Optimising what compounds.",
            primaryGoal: "Recovery",
            mealHistory: buildMealHistory(referenceDate: referenceDate),
            healthKitNutritionEnabled: true,
            outcomeHistory: buildOutcomes(referenceDate: referenceDate),
            labHistory: buildLabs(referenceDate: referenceDate),
            weeklySummaryEnabled: true,
            weeklySummaries: buildWeeklySummaries(referenceDate: referenceDate, entries: entries)
        )

        return profile
    }

    // MARK: - Weight

    /// 14-day weight series trending 80.2 kg → 78.4 kg. Smooth
    /// downward curve so the sparkline on the body trends section
    /// reads as a clean "I'm making progress" line.
    private static func buildWeightHistory(referenceDate: Date) -> [WeightEntry] {
        let start = 80.2
        let end = 78.4
        let count = 14
        return (0..<count).compactMap { offset in
            let day = Calendar.current.date(byAdding: .day, value: -(count - 1 - offset), to: referenceDate)
            guard let day else { return nil }
            // Light random-feeling wave so the line isn't perfectly straight.
            let progress = Double(offset) / Double(count - 1)
            let base = start + (end - start) * progress
            let wobble = sin(Double(offset) * 0.9) * 0.08
            return WeightEntry(date: day, kg: base + wobble)
        }
    }

    // MARK: - Consumption

    /// Per-day macro buckets keyed by start-of-day strings. Six
    /// days of logging hovering around the 2400 kcal target.
    private static func buildConsumption(referenceDate: Date) -> [String: DailyConsumption] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        let templates: [(cal: Int, protein: Int, carbs: Int, fat: Int, water: Int)] = [
            (2380, 178, 235, 82, 64),
            (2410, 184, 241, 78, 80),
            (2295, 175, 220, 76, 56),
            (2440, 188, 248, 84, 72),
            (2350, 170, 232, 80, 64),
            (2410, 182, 238, 81, 88),
            (1620, 124, 162, 56, 48),  // today, mid-day so partial
        ]

        var buckets: [String: DailyConsumption] = [:]
        for (offset, t) in templates.enumerated() {
            guard let day = Calendar.current.date(
                byAdding: .day, value: -(templates.count - 1 - offset), to: referenceDate
            ) else { continue }
            let key = formatter.string(from: Calendar.current.startOfDay(for: day))
            buckets[key] = DailyConsumption(
                date: Calendar.current.startOfDay(for: day),
                caloriesKcal: t.cal,
                proteinG: t.protein,
                carbsG: t.carbs,
                fatG: t.fat,
                waterOz: t.water
            )
        }
        return buckets
    }

    // MARK: - Meals

    private static func buildMealHistory(referenceDate: Date) -> [MealEntry] {
        struct MealSpec {
            let dayOffset: Int
            let category: MealCategory
            let name: String
            let cal: Int
            let protein: Int
            let carbs: Int
            let fat: Int
            let hour: Int
        }

        let specs: [MealSpec] = [
            // Today
            MealSpec(dayOffset: 0, category: .breakfast, name: "Oats + whey + berries", cal: 540, protein: 42, carbs: 68, fat: 14, hour: 7),
            MealSpec(dayOffset: 0, category: .lunch,     name: "Chicken rice bowl",     cal: 720, protein: 52, carbs: 78, fat: 18, hour: 13),
            MealSpec(dayOffset: 0, category: .snack,     name: "Greek yogurt + honey",  cal: 360, protein: 30, carbs: 16, fat: 24, hour: 16),
            // Yesterday
            MealSpec(dayOffset: 1, category: .breakfast, name: "Eggs + sourdough",      cal: 480, protein: 32, carbs: 36, fat: 22, hour: 8),
            MealSpec(dayOffset: 1, category: .lunch,     name: "Steak salad",           cal: 620, protein: 48, carbs: 22, fat: 38, hour: 13),
            MealSpec(dayOffset: 1, category: .dinner,    name: "Salmon + sweet potato", cal: 740, protein: 52, carbs: 64, fat: 26, hour: 19),
            MealSpec(dayOffset: 1, category: .snack,     name: "Protein bar",           cal: 240, protein: 20, carbs: 22, fat: 8,  hour: 21),
            // 2 days ago
            MealSpec(dayOffset: 2, category: .breakfast, name: "Smoothie bowl",         cal: 460, protein: 38, carbs: 54, fat: 12, hour: 8),
            MealSpec(dayOffset: 2, category: .lunch,     name: "Turkey wrap",           cal: 540, protein: 36, carbs: 52, fat: 18, hour: 13),
            MealSpec(dayOffset: 2, category: .dinner,    name: "Pasta primavera",       cal: 660, protein: 26, carbs: 92, fat: 18, hour: 19),
            // 3 days ago
            MealSpec(dayOffset: 3, category: .breakfast, name: "Oats + whey",           cal: 480, protein: 40, carbs: 56, fat: 12, hour: 7),
            MealSpec(dayOffset: 3, category: .lunch,     name: "Burrito bowl",          cal: 780, protein: 46, carbs: 88, fat: 26, hour: 13),
            MealSpec(dayOffset: 3, category: .dinner,    name: "Chicken + quinoa",      cal: 580, protein: 48, carbs: 56, fat: 16, hour: 19),
            // Older
            MealSpec(dayOffset: 4, category: .lunch,     name: "Poke bowl",             cal: 640, protein: 42, carbs: 72, fat: 18, hour: 13),
            MealSpec(dayOffset: 5, category: .dinner,    name: "Ribeye + asparagus",    cal: 820, protein: 64, carbs: 14, fat: 56, hour: 19),
            MealSpec(dayOffset: 6, category: .breakfast, name: "Avocado toast + eggs",  cal: 540, protein: 28, carbs: 38, fat: 32, hour: 8),
        ]

        return specs.map { spec in
            let day = Calendar.current.date(byAdding: .day, value: -spec.dayOffset, to: referenceDate) ?? referenceDate
            let date = Calendar.current.date(bySettingHour: spec.hour, minute: 0, second: 0, of: day) ?? day
            return MealEntry(
                date: date,
                category: spec.category,
                name: spec.name,
                calories: spec.cal,
                proteinG: spec.protein,
                carbsG: spec.carbs,
                fatG: spec.fat,
                source: .manual
            )
        }
    }

    // MARK: - Outcomes

    /// 14 daily check-ins trending from a composite ~3.6 → 4.3.
    /// Each dimension hand-tuned so it doesn't feel like one
    /// metronome — energy rises faster than recovery, mood is
    /// stable, focus dips mid-week and recovers. Reads as real
    /// life, not a metric stamp.
    private static func buildOutcomes(referenceDate: Date) -> [OutcomeEntry] {
        let scripts: [(energy: Int, sleep: Int, recovery: Int, mood: Int, focus: Int)] = [
            // 14 days ago → today
            (3, 4, 3, 4, 3),
            (4, 3, 3, 4, 4),
            (4, 4, 4, 4, 3),
            (3, 4, 3, 3, 4),
            (4, 4, 4, 4, 4),
            (4, 5, 4, 4, 4),
            (4, 4, 4, 5, 3),
            (5, 4, 4, 4, 4),
            (4, 5, 5, 4, 4),
            (5, 5, 4, 5, 4),
            (4, 4, 5, 5, 5),
            (5, 5, 4, 5, 4),
            (5, 4, 5, 4, 5),
            (5, 5, 5, 5, 4),
        ]
        return scripts.enumerated().compactMap { offset, s in
            guard let day = Calendar.current.date(byAdding: .day, value: -(scripts.count - 1 - offset), to: referenceDate)
            else { return nil }
            return OutcomeEntry(
                date: day,
                energy: s.energy,
                sleepQuality: s.sleep,
                recovery: s.recovery,
                mood: s.mood,
                focus: s.focus
            )
        }
    }

    // MARK: - Labs

    /// Two draws per panel so the trend chart has something to
    /// draw. Recent panel is March-ish, prior is ~6 weeks earlier.
    /// Values land inside reference range so the chart's band
    /// overlay reads cleanly.
    private static func buildLabs(referenceDate: Date) -> [LabValue] {
        let recent = Calendar.current.date(byAdding: .day, value: -10, to: referenceDate) ?? referenceDate
        let prior = Calendar.current.date(byAdding: .day, value: -55, to: referenceDate) ?? referenceDate

        return [
            // Sex hormones
            LabValue(date: recent, panel: .totalTestosterone, value: 782, source: "Quest"),
            LabValue(date: prior,  panel: .totalTestosterone, value: 718, source: "Quest"),
            LabValue(date: recent, panel: .freeTestosterone, value: 18.4, source: "Quest"),
            LabValue(date: prior,  panel: .freeTestosterone, value: 16.9, source: "Quest"),
            // Growth
            LabValue(date: recent, panel: .igf1, value: 218, source: "Marek Health"),
            LabValue(date: prior,  panel: .igf1, value: 196, source: "Marek Health"),
            // Metabolic
            LabValue(date: recent, panel: .hba1c, value: 5.2, source: "Quest"),
            LabValue(date: recent, panel: .fastingGlucose, value: 86, source: "Quest"),
            // Lipids
            LabValue(date: recent, panel: .hdl, value: 58, source: "Quest"),
            LabValue(date: recent, panel: .triglycerides, value: 78, source: "Quest"),
        ]
    }

    // MARK: - Workouts

    private static func buildWorkouts(referenceDate: Date) -> [WorkoutEntry] {
        let specs: [(dayOffset: Int, name: String, sets: Int, reps: Int, minutes: Int)] = [
            (0, "Push day", 18, 96, 62),
            (1, "Zone 2 cardio", 0, 0, 45),
            (2, "Pull day", 20, 110, 68),
            (3, "Rest", 0, 0, 0),
            (4, "Leg day", 22, 120, 74),
            (5, "Mobility", 0, 0, 30),
            (6, "Push day", 18, 100, 64),
        ]
        return specs.compactMap { spec in
            guard spec.minutes > 0 else { return nil }
            guard let day = Calendar.current.date(byAdding: .day, value: -spec.dayOffset, to: referenceDate)
            else { return nil }
            return WorkoutEntry(
                date: day,
                name: spec.name,
                sets: spec.sets,
                reps: spec.reps,
                durationMinutes: spec.minutes
            )
        }
    }

    // MARK: - Weekly recap

    /// Pre-generated recap for the current ISO week so the
    /// Today hero card lands in `.ready` state immediately.
    /// Keyed by the Monday's ISO date so the
    /// `WeeklySummaryService` cache lookup hits on first read.
    private static func buildWeeklySummaries(
        referenceDate: Date,
        entries: [ProtocolEntry]
    ) -> [String: WeeklySummary] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: referenceDate)
        else { return [:] }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let weekStart = formatter.string(from: interval.start)

        let text = """
        Strong week — 19 of 21 doses logged, a 14-day streak holding through the weekend, and your daily check-ins climbed to a 4.4 of 5 composite. Sleep quality led the rebound at 4.6, recovery followed at 4.4, and focus settled at 4.0 after a midweek dip.

        Biometrics moved alongside the cadence: HRV averaged 62 ms (up 5 ms versus last week) and resting heart rate held at 58 bpm. Nutrition stayed on target — 2,380 kcal average across six logging days, well inside your 2,400 kcal goal.

        Keep the same rhythm next week. Consistency at this level compounds — and your numbers are starting to show it.
        """

        let summary = WeeklySummary(
            weekStart: weekStart,
            text: text,
            keyStats: WeeklySummary.KeyStats(
                compliancePct: 0.905,
                dosesCompleted: 19,
                dosesTotal: 21,
                currentStreak: 14,
                avgCheckInScore: 4.4,
                avgCalories: 2380,
                hrvDelta: 5
            ),
            kind: .ai,
            generatedAt: Date()
        )

        return [weekStart: summary]
    }
}
