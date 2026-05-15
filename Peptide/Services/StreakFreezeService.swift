import Foundation

/// Streak freeze accounting. One free freeze per calendar month
/// (rolling reset on the 1st), redeemable as a shield against a
/// single missed day. The freeze is consumed when the user
/// explicitly taps "Use freeze" on the at-risk prompt — never
/// automatically — so it can't be silently spent.
///
/// Pure-function over the profile's `streakFreezeDays` set, which
/// stores the start-of-day ISO strings the streak engine treats
/// as counted-as-completed.
enum StreakFreezeService {

    /// How many freezes the user gets per calendar month. Single-
    /// digit by design: the freeze is a "you had one bad day"
    /// affordance, not a "skip whenever" excuse.
    static let freezesPerMonth: Int = 1

    /// True when the user has at least one unused freeze this
    /// month. Drives whether the at-risk prompt shows the
    /// freeze button.
    static func hasFreezeAvailable(in profile: UserProfile, now: Date = Date()) -> Bool {
        usedThisMonth(in: profile, now: now) < freezesPerMonth
    }

    /// Number of freezes redeemed this calendar month. Drives the
    /// subtitle copy ("0/1 used this month") in the streak detail.
    static func usedThisMonth(in profile: UserProfile, now: Date = Date()) -> Int {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: now)
        guard let monthStart = cal.date(from: comps) else { return 0 }
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        return profile.streakFreezeDays.compactMap { key -> Date? in
            isoFormatter.date(from: key)
        }
        .filter { $0 >= monthStart && $0 < monthEnd }
        .count
    }

    /// Returns the ISO key for a given calendar date. Used by the
    /// streak engine to check membership.
    static func dayKey(for date: Date) -> String {
        let day = Calendar.current.startOfDay(for: date)
        return isoFormatter.string(from: day)
    }

    /// True when the given date has a freeze applied. Streak
    /// engine treats these the same as completed days for the
    /// purpose of consecutive-day counting.
    static func isFrozen(_ date: Date, in profile: UserProfile) -> Bool {
        profile.streakFreezeDays.contains(dayKey(for: date))
    }

    /// Spends one freeze on the most recent at-risk day. Idempotent
    /// — re-tapping doesn't double-spend. Returns true when the
    /// freeze was applied, false when the budget is exhausted or
    /// the target day is already covered.
    @discardableResult
    static func applyFreeze(
        in profile: inout UserProfile,
        for date: Date,
        now: Date = Date()
    ) -> Bool {
        let key = dayKey(for: date)
        guard !profile.streakFreezeDays.contains(key) else { return false }
        guard hasFreezeAvailable(in: profile, now: now) else { return false }
        profile.streakFreezeDays.insert(key)
        return true
    }

    // ISO8601DateFormatter is documented as thread-safe by Apple but
    // not marked Sendable, so Swift 6 strict concurrency rejects it
    // as global shared state. `nonisolated(unsafe)` opts out of the
    // check — the underlying type's documented thread safety holds,
    // and the formatter is only ever read (never mutated) after the
    // closure that builds it.
    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
