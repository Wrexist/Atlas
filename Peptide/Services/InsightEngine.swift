import Foundation

struct InsightEngine {
    struct Insight: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let description: String
        let type: InsightType
    }

    enum InsightType {
        case positive
        case warning
        case neutral
    }

    /// `frozenDayKeys` comes from `UserProfile.streakFreezeDays`. It
    /// defaults to empty only so tests that don't exercise freezes stay
    /// terse — production callers pass the profile's set, or the insight
    /// line quotes a lower streak than the home ring.
    static func generateInsights(
        from entries: [ProtocolEntry],
        protocols: [PeptideProtocol],
        frozenDayKeys: Set<String> = []
    ) -> [Insight] {
        var insights: [Insight] = []
        let calendar = Calendar.current

        // Streak insights
        let currentStreak = StreakEngine.currentStreak(
            entriesByDay: StreakEngine.activeEntriesByDay(entries: entries, protocols: protocols),
            frozenDayKeys: frozenDayKeys
        )
        if currentStreak >= 30 {
            insights.append(Insight(icon: "flame.fill", title: "Incredible consistency!", description: "You're on a \(currentStreak)-day streak. Top-tier dedication.", type: .positive))
        } else if currentStreak >= 7 {
            insights.append(Insight(icon: "flame.fill", title: "Strong streak!", description: "\(currentStreak) days in a row. Keep the momentum going.", type: .positive))
        }

        // Day-of-week analysis
        let dayMissPatterns = analyzeDayPatterns(entries: entries)
        if let worstDay = dayMissPatterns.max(by: { $0.value < $1.value }), worstDay.value > 0.3 {
            let dayNames = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            let dayName = worstDay.key >= 1 && worstDay.key <= 7 ? dayNames[worstDay.key] : "unknown"
            insights.append(Insight(icon: "calendar.badge.exclamationmark", title: "Pattern detected", description: "You tend to miss doses on \(dayName)s. Consider setting an extra reminder.", type: .warning))
        }

        // Time-of-day analysis
        let eveningEntries = entries.filter {
            let hour = calendar.component(.hour, from: $0.date)
            return hour >= 18
        }
        let eveningMissRate = eveningEntries.isEmpty ? 0 : Double(eveningEntries.filter { !$0.completed }.count) / Double(eveningEntries.count)
        if eveningMissRate > 0.3 && eveningEntries.count > 5 {
            insights.append(Insight(icon: "moon.fill", title: "Evening doses need attention", description: "You miss \(Int(eveningMissRate * 100))% of evening doses. Try linking them to a routine.", type: .warning))
        }

        // Compliance trend: compare last 7 days vs preceding 8-30 days (non-overlapping)
        let recentCompliance = complianceForRange(entries: entries, days: 7)
        let olderCompliance = complianceForExclusiveRange(entries: entries, from: 30, to: 7)
        if recentCompliance > olderCompliance + 0.1 && olderCompliance > 0 {
            insights.append(Insight(icon: "arrow.up.right", title: "Compliance improving", description: "Your 7-day compliance is \(Int(recentCompliance * 100))%, up from \(Int(olderCompliance * 100))% prior average.", type: .positive))
        } else if recentCompliance < olderCompliance - 0.15 && olderCompliance > 0 {
            insights.append(Insight(icon: "arrow.down.right", title: "Compliance dipping", description: "Recent compliance dropped to \(Int(recentCompliance * 100))%. Prior average was \(Int(olderCompliance * 100))%.", type: .warning))
        }

        // Protocol count
        let activeCount = protocols.filter { $0.status == .active }.count
        if activeCount >= 3 {
            insights.append(Insight(icon: "exclamationmark.triangle", title: "Many active protocols", description: "Running \(activeCount) protocols. Consider focusing on fewer for better compliance.", type: .neutral))
        }

        // Adaptive reminders: detect a consistent drift between
        // scheduled and actual log times. If the user's last 10
        // completed entries skew > 30 minutes off in a consistent
        // direction, surface a "shift the schedule by N minutes?"
        // nudge so the reminder stops firing at a wrong time.
        if let drift = detectDoseTimeDrift(entries: entries) {
            insights.append(Insight(
                icon: "clock.badge.exclamationmark",
                title: "Your reminders may be off",
                description: drift.copy,
                type: .neutral
            ))
        }

        // Total doses milestone
        let totalCompleted = entries.filter(\.completed).count
        let milestones = [50, 100, 250, 500, 1000]
        for milestone in milestones where totalCompleted >= milestone && totalCompleted < milestone + 10 {
            insights.append(Insight(icon: "star.fill", title: "Milestone reached!", description: "You've logged over \(milestone) doses. Outstanding commitment.", type: .positive))
            break
        }

        return insights
    }

    /// Per-weekday miss rate. Gate at minimum 4 observations per day
    /// so a user who missed their first Tuesday dose (1/1 = 100%)
    /// doesn't trigger a "you tend to miss Tuesdays" false pattern
    /// (audit Insights H5). Days with fewer than 4 entries return 0
    /// (treated as no signal by downstream consumers' > 0.3 gate).
    private static let dayPatternMinObservations = 4

    private static func analyzeDayPatterns(entries: [ProtocolEntry]) -> [Int: Double] {
        let calendar = Calendar.current
        var dayMissRates: [Int: (missed: Int, total: Int)] = [:]

        for entry in entries {
            let weekday = calendar.component(.weekday, from: entry.date)
            let isoDay = weekday == 1 ? 7 : weekday - 1
            var current = dayMissRates[isoDay, default: (0, 0)]
            current.total += 1
            if !entry.completed { current.missed += 1 }
            dayMissRates[isoDay] = current
        }

        return dayMissRates.mapValues { pair in
            guard pair.total >= dayPatternMinObservations else { return 0 }
            return Double(pair.missed) / Double(pair.total)
        }
    }

    private static func complianceForRange(entries: [ProtocolEntry], days: Int) -> Double {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: Date()) else { return 0 }
        let rangeEntries = entries.filter { $0.date >= cutoff }
        guard !rangeEntries.isEmpty else { return 0 }
        return Double(rangeEntries.filter(\.completed).count) / Double(rangeEntries.count)
    }

    private static func complianceForExclusiveRange(entries: [ProtocolEntry], from outerDays: Int, to innerDays: Int) -> Double {
        let calendar = Calendar.current
        guard let outerCutoff = calendar.date(byAdding: .day, value: -outerDays, to: Date()),
              let innerCutoff = calendar.date(byAdding: .day, value: -innerDays, to: Date()) else { return 0 }
        let rangeEntries = entries.filter { $0.date >= outerCutoff && $0.date < innerCutoff }
        guard !rangeEntries.isEmpty else { return 0 }
        return Double(rangeEntries.filter(\.completed).count) / Double(rangeEntries.count)
    }

    /// Adaptive-reminder trigger. Looks at the most recent N
    /// completed entries that have an `actualTime` recorded
    /// (camera barcode scan + Live Activity completion both stamp
    /// it), computes the median signed-minute delta against the
    /// scheduled time, and returns a trigger when both:
    ///
    ///   1. The sample size is enough to be confident (≥ 10).
    ///   2. The median drift is ≥ 30 minutes in a consistent
    ///      direction (≥ 70% of entries on the same side).
    ///
    /// This catches the user who's been logging their 8:00 AM
    /// dose at 8:35 AM for two weeks without surfacing noise on
    /// a user whose timing is genuinely scattered.
    private static func detectDoseTimeDrift(entries: [ProtocolEntry]) -> DoseDrift? {
        let calendar = Calendar.current
        let recentCompleted = entries
            .filter { $0.completed && $0.actualTime != nil }
            .sorted { $0.date > $1.date }
            .prefix(20)

        guard recentCompleted.count >= 10 else { return nil }

        // Compute signed minute delta (actual − scheduled) for
        // each entry, normalising same-day so a midnight rollover
        // doesn't read as a 23-hour drift.
        let deltas: [Int] = recentCompleted.compactMap { entry in
            guard let actual = entry.actualTime else { return nil }
            let scheduledHM = calendar.dateComponents([.hour, .minute], from: entry.date)
            let actualHM = calendar.dateComponents([.hour, .minute], from: actual)
            guard let sH = scheduledHM.hour, let sM = scheduledHM.minute,
                  let aH = actualHM.hour, let aM = actualHM.minute
            else { return nil }
            let scheduledMin = sH * 60 + sM
            let actualMin = aH * 60 + aM
            var delta = actualMin - scheduledMin
            // Wrap into [-720, 720] so a "23 hours late" is read
            // as "1 hour early" for the same-day comparison.
            if delta > 720 { delta -= 1440 }
            if delta < -720 { delta += 1440 }
            return delta
        }
        guard deltas.count >= 10 else { return nil }

        let positiveCount = deltas.filter { $0 > 0 }.count
        let negativeCount = deltas.filter { $0 < 0 }.count
        let total = deltas.count
        let directionFraction = Double(max(positiveCount, negativeCount)) / Double(total)
        guard directionFraction >= 0.7 else { return nil }

        let sortedDeltas = deltas.sorted()
        let median = sortedDeltas[sortedDeltas.count / 2]
        let absMedian = abs(median)
        guard absMedian >= 30 else { return nil }

        let copy = median > 0
            ? "You log doses about \(absMedian) min later than scheduled. Consider shifting your reminder."
            : "You log doses about \(absMedian) min earlier than scheduled. Consider shifting your reminder."
        return DoseDrift(medianMinutes: median, copy: copy)
    }

    private struct DoseDrift {
        let medianMinutes: Int
        let copy: String
    }
}
