import Foundation

/// Rewrites the Title Case goal labels the old profile-customization picker
/// stored ("Better Sleep", "Fat Loss", ...) as the `OnboardingView.PrimaryGoal`
/// keys every goal editor now reads. Without it those goals stay invisible in
/// both editors while still steering recommendations.
enum LegacyGoalMigration {
    private static let renamed: [String: OnboardingView.PrimaryGoal] = [
        "Muscle Recovery": .recovery,
        "Joint Health": .recovery,
        "Better Sleep": .betterSleep,
        "Anti-Aging": .antiAging,
        "Fat Loss": .loseFat,
    ]

    /// Old labels with no current goal. Dropped rather than kept as goals no
    /// editor can show or remove.
    private static let retired: Set<String> = [
        "Cognitive Edge",
        "Immune Support",
        "Stress Reduction",
    ]

    /// Idempotent: keys and unrelated strings pass through unchanged. The pin
    /// follows its goal and is cleared when that goal is retired.
    static func migrate(goals: [String], primaryGoal: String?) -> (goals: [String], primaryGoal: String?) {
        var seen = Set<String>()
        let migratedGoals = goals.compactMap(key(for:)).filter { seen.insert($0).inserted }
        let migratedPrimary = primaryGoal.flatMap(key(for:)).flatMap { migratedGoals.contains($0) ? $0 : nil }
        return (migratedGoals, migratedPrimary)
    }

    private static func key(for goal: String) -> String? {
        if retired.contains(goal) { return nil }
        return renamed[goal]?.rawValue ?? goal
    }
}
