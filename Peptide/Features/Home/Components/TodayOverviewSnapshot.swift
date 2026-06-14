import Foundation

/// Pure data describing what the Home overview card renders.
/// Built once per `DataStore` read so the view doesn't have to
/// reach into five different services on every redraw — and so
/// the snapshot is unit-testable in isolation from `DataStore`.
///
/// Every field is optional or has a "not yet tracked" sentinel so
/// the card can render gracefully for a brand-new user with no
/// protocols, no nutrition target, and no labs. Once the user
/// fills in any one domain, that tile lights up; the rest stay
/// in their soft empty state.
struct TodayOverviewSnapshot: Equatable, Sendable {

    // MARK: - Hero: protocol compliance

    /// Compliance fraction for today's scheduled doses — drives the
    /// hero ring. `nil` when the user has zero protocols (the card
    /// suppresses the ring entirely and shows the empty hero copy).
    let complianceFraction: Double?
    let dosesCompletedToday: Int
    let dosesTotalToday: Int
    /// Next pending dose this calendar day, if any. When `nil` and
    /// `dosesTotalToday > 0`, the hero flips to the "all logged"
    /// celebratory state.
    let nextDose: ProtocolEntry?
    /// All-time dose-completion streak in calendar days. Surfaced as
    /// a small subtitle under the hero copy.
    let doseStreak: Int

    // MARK: - Nutrition

    /// Calories logged so far today. Always populated (zero when
    /// nothing logged) so the tile can render a 0% ring.
    let caloriesToday: Int
    /// Target calories — populated from `NutritionTargets`. `nil`
    /// flips the tile to the "set a goal" empty state.
    let calorieTarget: Int?
    /// Water ounces logged today. Same zero-vs-nil semantics as
    /// `caloriesToday` — always populated.
    let waterToday: Int

    // MARK: - Lifestyle streak

    /// Active meal-logging streak in calendar days. Drives the
    /// flame tile.
    let mealStreak: Int

    // MARK: - Daily check-in

    /// Today's outcome composite (1.0–5.0). `nil` when the user
    /// hasn't filled in today's check-in — the tile flips to a CTA
    /// instead of a number.
    let checkInScore: Double?

    // MARK: - Latest lab

    /// Most-recent lab draw across all panels — surfaced on the
    /// rotating bottom insight row. `nil` when the user has no
    /// labs logged at all.
    let latestLab: LatestLabSummary?

    /// Short label for the rotating bottom insight. Picked from
    /// the highest-priority signal we have (insight engine output,
    /// most-recent lab, or a fallback nudge). `nil` lets the card
    /// hide the row entirely on a brand-new install.
    let bottomInsight: BottomInsight?

    struct LatestLabSummary: Equatable, Sendable {
        let panelShortName: String
        let valueDisplay: String
        let daysAgo: Int
    }

    /// Discriminated union for the rotating bottom insight. Each
    /// case carries the precomputed display strings + an SF Symbol
    /// hint so the view layer is a pure render of the snapshot.
    enum BottomInsight: Equatable, Sendable {
        /// Output of the protocol insight engine — "Best on
        /// Tuesday", "You're 2 doses from a record streak", etc.
        case protocolInsight(title: String, body: String, icon: String)
        /// Latest lab draw — "Total T up 24 ng/dL since Apr 12".
        case latestLab(title: String, body: String, icon: String)
        /// Fallback nudge when no other signal is available. Carries
        /// the destination the row should open when tapped so the host
        /// routes it without matching on the (localized) title.
        case nudge(title: String, body: String, icon: String, action: NudgeAction)

        /// Where a tapped nudge takes the user.
        enum NudgeAction: Equatable, Sendable {
            case setCalorieTarget
            case logMeal
        }

        var icon: String {
            switch self {
            case .protocolInsight(_, _, let icon),
                 .latestLab(_, _, let icon),
                 .nudge(_, _, let icon, _):
                return icon
            }
        }

        var title: String {
            switch self {
            case .protocolInsight(let title, _, _),
                 .latestLab(let title, _, _),
                 .nudge(let title, _, _, _):
                return title
            }
        }

        var body: String {
            switch self {
            case .protocolInsight(_, let body, _),
                 .latestLab(_, let body, _),
                 .nudge(_, let body, _, _):
                return body
            }
        }
    }

    // MARK: - Derived

    /// Has the user supplied enough data anywhere to justify the
    /// card? When false the host can suppress it (zero protocols +
    /// no nutrition target + no meals + no labs is a brand-new
    /// install — the existing getting-started card already covers
    /// them better than a sea of empty tiles).
    var hasAnySignal: Bool {
        if (dosesTotalToday > 0) { return true }
        if mealStreak > 0 || caloriesToday > 0 || waterToday > 0 { return true }
        if calorieTarget != nil { return true }
        if checkInScore != nil { return true }
        if latestLab != nil { return true }
        return false
    }
}

extension TodayOverviewSnapshot {

    /// Builds the snapshot from the live `DataStore`. Pure with
    /// respect to the store — reads every field once and computes
    /// the bottom-insight selection on the spot so the card's
    /// render is just a flat layout pass.
    @MainActor
    static func build(from dataStore: DataStore, now: Date = Date()) -> TodayOverviewSnapshot {
        let entries = dataStore.todayEntries
        let total = entries.count
        let completed = entries.filter(\.completed).count
        let fraction: Double? = total > 0 ? Double(completed) / Double(total) : nil

        let consumption = dataStore.consumption()
        let targets = dataStore.profile.nutritionTargets

        let lab = latestLab(in: dataStore, now: now)
        let bottom = pickBottomInsight(
            engineInsight: dataStore.topInsight,
            latestLab: lab,
            mealStreak: dataStore.mealLoggingStreak,
            hasTarget: targets != nil
        )

        return TodayOverviewSnapshot(
            complianceFraction: fraction,
            dosesCompletedToday: completed,
            dosesTotalToday: total,
            nextDose: dataStore.nextDose,
            doseStreak: dataStore.currentStreak,
            caloriesToday: consumption.caloriesKcal,
            calorieTarget: targets?.calories,
            waterToday: consumption.waterOz,
            mealStreak: dataStore.mealLoggingStreak,
            checkInScore: dataStore.outcome(for: now)?.composite,
            latestLab: lab,
            bottomInsight: bottom
        )
    }

    /// Shared lab-value formatter. MainActor-isolated because it's mutated
    /// per call (fraction digits) and only ever used from `latestLab`.
    @MainActor private static let labValueFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        return f
    }()

    @MainActor
    private static func latestLab(in dataStore: DataStore, now: Date) -> LatestLabSummary? {
        guard let newest = dataStore.profile.labHistory.max(by: { $0.date < $1.date })
        else { return nil }
        // Reuse a MainActor-isolated formatter (build runs per HomeView body
        // pass); only the dynamic fraction-digit setting changes per call.
        let formatter = Self.labValueFormatter
        formatter.maximumFractionDigits = newest.value < 10 ? 1 : 0
        let valueDisplay: String = {
            let number = formatter.string(from: newest.value as NSNumber) ?? "\(newest.value)"
            let unit = newest.panel.canonicalUnit
            return unit.isEmpty ? number : "\(number) \(unit)"
        }()
        let days = max(0, Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: newest.date),
            to: Calendar.current.startOfDay(for: now)
        ).day ?? 0)
        return LatestLabSummary(
            panelShortName: newest.panel.shortName,
            valueDisplay: valueDisplay,
            daysAgo: days
        )
    }

    /// Priority order:
    /// 1. Protocol insight engine — has the most personalised signal
    /// 2. Latest lab — if it's within the last 60 days
    /// 3. Nudge based on what the user hasn't set up yet
    /// 4. nil — let the row collapse on a brand-new install
    private static func pickBottomInsight(
        engineInsight: InsightEngine.Insight?,
        latestLab: LatestLabSummary?,
        mealStreak: Int,
        hasTarget: Bool
    ) -> BottomInsight? {
        if let insight = engineInsight {
            return .protocolInsight(
                title: insight.title,
                body: insight.description,
                icon: insight.icon
            )
        }
        if let lab = latestLab, lab.daysAgo <= 60 {
            let body = lab.daysAgo == 0
                ? String(localized: "Logged today")
                : String(format: String(localized: "Logged %d days ago"), lab.daysAgo)
            return .latestLab(
                title: "\(lab.panelShortName) — \(lab.valueDisplay)",
                body: body,
                icon: "testtube.2"
            )
        }
        if !hasTarget {
            return .nudge(
                title: String(localized: "Set a calorie target"),
                body: String(localized: "Unlocks the macro rings and Watch glance."),
                icon: "target",
                action: .setCalorieTarget
            )
        }
        if mealStreak == 0 {
            return .nudge(
                title: String(localized: "Log a meal to start a streak"),
                body: String(localized: "Scan a barcode or pick from your saved foods."),
                icon: "fork.knife",
                action: .logMeal
            )
        }
        return nil
    }
}
