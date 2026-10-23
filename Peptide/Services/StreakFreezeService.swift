import Foundation

/// Streak freeze accounting. One free freeze per calendar month
/// (rolling reset on the 1st), redeemable as a shield against a
/// single missed day. The freeze is consumed when the user
/// explicitly taps "Use freeze" on the at-risk prompt — never
/// automatically — so it can't be silently spent.
///
/// Pure-function over the profile's `streakFreezeDays` set, which
/// stores the local calendar dates (`yyyyMMdd`) the streak engine
/// treats as counted-as-completed.
enum StreakFreezeService {

    /// How many freezes the user gets per calendar month. Single-
    /// digit by design: the freeze is a "you had one bad day"
    /// affordance, not a "skip whenever" excuse.
    static let freezesPerMonth: Int = 1

    /// True when the user has at least one unused freeze this
    /// month. Drives whether the at-risk prompt shows the
    /// freeze button.
    static func hasFreezeAvailable(
        in profile: UserProfile,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        usedThisMonth(in: profile, now: now, calendar: calendar) < freezesPerMonth
    }

    /// Number of freezes redeemed this calendar month. Drives the
    /// subtitle copy ("0/1 used this month") in the streak detail.
    static func usedThisMonth(
        in profile: UserProfile,
        now: Date = Date(),
        calendar cal: Calendar = .current
    ) -> Int {
        let comps = cal.dateComponents([.year, .month], from: now)
        guard let monthStart = cal.date(from: comps),
              let days = cal.range(of: .day, in: .month, for: monthStart)
        else { return 0 }
        // Keys are compared with keys built the same way they were
        // stored. Parsing a key back to a date read it as GMT midnight,
        // so outside UTC a freeze on the 1st counted against the
        // previous month's budget.
        let monthKeys = Set(days.compactMap { day in
            cal.date(byAdding: .day, value: day - 1, to: monthStart).map { dayKey(for: $0, calendar: cal) }
        })
        return profile.streakFreezeDays.intersection(monthKeys).count
    }

    /// The key for the local calendar day containing `date`, e.g.
    /// "20261023". Built from the calendar's own year/month/day so it
    /// names the day the user saw, in any time zone.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// True when the given date has a freeze applied. Streak
    /// engine treats these the same as completed days for the
    /// purpose of consecutive-day counting.
    static func isFrozen(_ date: Date, in profile: UserProfile, calendar: Calendar = .current) -> Bool {
        profile.streakFreezeDays.contains(dayKey(for: date, calendar: calendar))
    }

    /// Rewrites keys stored by builds that formatted local midnight in
    /// GMT ("2026-10-22" for a 23 October freeze east of UTC) as local
    /// `dayKey`s. The two formats differ, so this is idempotent and safe
    /// to run on keys merged in from another device. Assumes the legacy
    /// key was written in `calendar`'s time zone: east of UTC local
    /// midnight falls on the previous GMT date, elsewhere on the same one.
    static func migratingLegacyKeys(_ keys: Set<String>, calendar: Calendar = .current) -> Set<String> {
        Set(keys.map { key in
            guard key.contains("-"), let gmtMidnight = legacyFormatter.date(from: key) else { return key }
            let gmtNoon = gmtMidnight.addingTimeInterval(12 * 3600)
            let shift = calendar.timeZone.secondsFromGMT(for: gmtNoon) > 0 ? 1 : 0
            var gmt = Calendar(identifier: .gregorian)
            gmt.timeZone = TimeZone(identifier: "GMT")!
            let localDay = gmt.date(byAdding: .day, value: shift, to: gmtMidnight) ?? gmtMidnight
            return dayKey(for: localDay, calendar: gmt)
        })
    }

    /// Spends one freeze on the most recent at-risk day. Idempotent
    /// — re-tapping doesn't double-spend. Returns true when the
    /// freeze was applied, false when the budget is exhausted or
    /// the target day is already covered.
    @discardableResult
    static func applyFreeze(
        in profile: inout UserProfile,
        for date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let key = dayKey(for: date, calendar: calendar)
        guard !profile.streakFreezeDays.contains(key) else { return false }
        // The budget is the frozen day's month, not today's: on the 1st,
        // freezing the 31st must spend the previous month's freeze.
        guard hasFreezeAvailable(in: profile, now: date, calendar: calendar) else { return false }
        profile.streakFreezeDays.insert(key)
        return true
    }

    // Parses the legacy "yyyy-MM-dd" GMT keys. ISO8601DateFormatter is
    // documented as thread-safe but not marked Sendable, so
    // `nonisolated(unsafe)` opts out of the global-state check; the
    // formatter is only read after the closure that builds it.
    nonisolated(unsafe) private static let legacyFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
