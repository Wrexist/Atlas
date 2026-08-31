import Foundation

/// Reconciles Atlas's several independent "what's my one thing" signals
/// into a single ranked `Reason` for the top of Today.
///
/// Before this engine, three call sites each picked their own "one thing"
/// with no arbitration between them: `CoachingMessageEngine` (recovery /
/// sleep / dose coaching), `DailyScheduleEngine.DailyPlan.headline` (today's
/// dose-plan guidance), and habits — which had no "one thing" picker at all,
/// since `CoachingMessageEngine` has never known habits exist. A user could
/// see "You're on track" in the coaching card while a whole habit ring sat
/// untouched below it.
///
/// `TodayOverviewSnapshot`'s rotating bottom insight is deliberately left
/// out of this reconciliation — Product Architecture 07 already scopes it
/// to the "analysis" zone below the fold, and it stays there; this engine
/// only unifies the *primary*, above-the-fold slot.
///
/// This engine calls `CoachingMessageEngine.pick(context:)` once and then
/// classifies a priority tier around it — deliberately re-walking that
/// engine's own branch conditions (see the inline comments below) rather
/// than re-deriving them independently, so a tier label can never disagree
/// with the message it's attached to. An earlier draft checked, e.g.,
/// "late in the day with pending doses" as its own independent condition;
/// with a *strong* recovery score that condition can also be true, but
/// `CoachingMessageEngine` would have already returned its strong-recovery
/// message — tagging that as a "time-sensitive catch-up" reason would have
/// been a real, if subtle, mislabeling. The time-sensitive check below is
/// therefore gated on `!isStrongRecovery`.
///
/// The weekly-review progress-insight half is deliberately checked
/// *before* the recovery half, not after: both share the `.progressInsight`
/// tier, but a real, concrete week-over-week diff ("compliance up 12%") is
/// a more useful and more specific line than the generic "recovery is
/// strong" status, so it should win whenever both are available — a
/// strong-recovery day that also has a fresh weekly review shows the
/// review, not the generic recovery line.
///
/// Pure function: no I/O, no singletons. Every underlying engine keeps its
/// own tested logic untouched — this only ranks their outputs.
enum PrimaryReasonEngine {

    /// Higher raw value = higher urgency. Ordering matches the retention
    /// brief's cascade: critical user value, then a concrete high-value
    /// action, then a time-sensitive nudge, then a progress insight, and
    /// finally an optional reminder.
    enum Priority: Int, Comparable, Sendable {
        case optionalReminder
        case progressInsight
        case timeSensitive
        case highValueAction
        case critical

        static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    struct Reason: Equatable, Sendable {
        let message: CoachingMessageEngine.CoachingMessage
        let priority: Priority
    }

    struct Context: Sendable {
        /// The same context `CoachingMessageEngine` consumes — reused
        /// rather than duplicated so the two engines never disagree about
        /// what "today" looks like.
        let coaching: CoachingMessageEngine.Context
        /// `DailyScheduleEngine.DailyPlan.headline`. Pass `nil` when the
        /// user has no protocols today at all (not merely none pending).
        let dailyPlanHeadline: String?
        let habitsDueCount: Int
        let habitsDoneCount: Int
        /// A real, non-noise week-over-week delta from
        /// `WeeklySummaryEngine.changeHeadline`, only when a weekly review
        /// is ready to view. `nil` when there's no review, or the review
        /// exists but nothing meaningfully changed — never a manufactured
        /// insight.
        let weeklyReviewHeadline: String?

        init(
            coaching: CoachingMessageEngine.Context,
            dailyPlanHeadline: String? = nil,
            habitsDueCount: Int = 0,
            habitsDoneCount: Int = 0,
            weeklyReviewHeadline: String? = nil
        ) {
            self.coaching = coaching
            self.dailyPlanHeadline = dailyPlanHeadline
            self.habitsDueCount = habitsDueCount
            self.habitsDoneCount = habitsDoneCount
            self.weeklyReviewHeadline = weeklyReviewHeadline
        }
    }

    // Mirrors CoachingMessageEngine's own thresholds exactly — see the
    // type-level doc comment on why these are re-walked rather than
    // re-derived.
    private static let strongRecoveryFloor = 75
    private static let weakRecoveryCeiling = 40
    private static let shortSleepCeiling: Double = 6.0
    private static let lateInDayHour = 18

    static func pick(context: Context) -> Reason {
        let cc = context.coaching
        let coaching = CoachingMessageEngine.pick(context: cc)

        // Onboarding states take absolute precedence in
        // CoachingMessageEngine's own cascade (its very first two
        // branches) — nothing here outranks getting a new or
        // disconnected user set up.
        if coaching.eyebrow == "WELCOME" || coaching.eyebrow == "GET STARTED" {
            return Reason(message: coaching, priority: .optionalReminder)
        }

        let isStrongRecovery = (cc.recoveryScore ?? Int.min) >= strongRecoveryFloor
        let isWeakRecovery = (cc.recoveryScore ?? Int.max) <= weakRecoveryCeiling
        let isShortSleep = cc.sleepHours.map { $0 > 0 && $0 < shortSleepCeiling } ?? false

        // Tier: CRITICAL — a genuine rest/safety signal. `isStrongRecovery`
        // is excluded from the short-sleep half exactly as
        // CoachingMessageEngine's cascade does (its short-sleep branch is
        // only reachable once strong AND weak recovery have both failed).
        if isWeakRecovery || (!isStrongRecovery && isShortSleep) {
            return Reason(message: coaching, priority: .critical)
        }

        // Tier: HIGH-VALUE ACTION — habits are due and none are done yet.
        // Pure upside: CoachingMessageEngine has no concept of habits, so
        // this slot was never competed for before. Checked ahead of
        // strong-recovery so a concrete action still outranks a purely
        // reflective status line, per the retention brief's cascade
        // (critical > high-value action > time-sensitive > progress
        // insight > optional).
        if context.habitsDueCount > 0, context.habitsDoneCount == 0 {
            return Reason(message: habitsMessage(context: context), priority: .highValueAction)
        }

        // Tier: TIME-SENSITIVE — day is running out with doses still
        // open. Gated on `!isStrongRecovery`: with a strong recovery
        // score, CoachingMessageEngine's own cascade would already have
        // returned its strong-recovery message rather than a catch-up
        // one, so `coaching` here would not actually be about catching
        // up — tagging it "time-sensitive" would mislabel it (see the
        // type-level doc comment). A strong-recovery day that's also
        // running out of doses instead falls through to the
        // weekly-review or recovery progress-insight tiers below.
        if cc.hourOfDay >= lateInDayHour, cc.pendingDoseCount > 0, !isStrongRecovery {
            return Reason(message: coaching, priority: .timeSensitive)
        }

        // Tier: PROGRESS INSIGHT (weekly-review half) — a real,
        // non-manufactured week-over-week diff. Checked ahead of the
        // generic recovery half below — see the type-level doc comment
        // on why a concrete diff wins over the generic status line.
        if let headline = context.weeklyReviewHeadline {
            return Reason(message: weeklyReviewMessage(headline: headline), priority: .progressInsight)
        }

        // Tier: PROGRESS INSIGHT (recovery half) — strong recovery, and
        // no weekly review available to show instead.
        if isStrongRecovery {
            return Reason(message: coaching, priority: .progressInsight)
        }

        // Default — the coaching engine's on-track fallback, enriched
        // with the dose-plan's more precise headline (fasted-first
        // ordering, conflict-aware) in place of the generic "Next: X at
        // Y" body that fallback uses.
        if let headline = context.dailyPlanHeadline, coaching.eyebrow == "ON TRACK" {
            return Reason(
                message: CoachingMessageEngine.CoachingMessage(
                    icon: coaching.icon,
                    eyebrow: coaching.eyebrow,
                    title: coaching.title,
                    body: headline,
                    tone: coaching.tone
                ),
                priority: .optionalReminder
            )
        }
        return Reason(message: coaching, priority: .optionalReminder)
    }

    private static func habitsMessage(context: Context) -> CoachingMessageEngine.CoachingMessage {
        let remaining = max(0, context.habitsDueCount - context.habitsDoneCount)
        let plural = remaining == 1 ? "habit" : "habits"
        return CoachingMessageEngine.CoachingMessage(
            icon: "checklist",
            eyebrow: "HABITS",
            title: "\(remaining) \(plural) due today",
            body: "Tap in below to check off your first one.",
            tone: .neutral
        )
    }

    private static func weeklyReviewMessage(headline: String) -> CoachingMessageEngine.CoachingMessage {
        CoachingMessageEngine.CoachingMessage(
            icon: "chart.line.uptrend.xyaxis",
            eyebrow: "WEEKLY REVIEW",
            title: "Your week in review",
            body: headline,
            tone: .positive
        )
    }
}
