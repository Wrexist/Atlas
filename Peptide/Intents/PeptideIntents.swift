import AppIntents
import Foundation

// MARK: - Next Dose Intent

struct NextDoseIntent: AppIntent {
    static let title: LocalizedStringResource = "What's My Next Dose?"
    static let description = IntentDescription("Shows your next scheduled peptide dose")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = await IntentDataSnapshot.load()
        guard !snapshot.protocols.isEmpty else {
            return .result(dialog: "No protocols found. Open PeptideX to get started.")
        }

        let calendar = Calendar.current
        let now = Date()
        let activeIds = Set(snapshot.protocols.filter { $0.status == .active }.map(\.id))
        let todayEntries = snapshot.entries
            .filter { calendar.isDateInToday($0.date) && activeIds.contains($0.protocolId) && !$0.completed }
            .sorted { $0.date < $1.date }

        guard let next = todayEntries.first(where: { $0.date > now }) ?? todayEntries.first else {
            return .result(dialog: "All doses completed for today! Great job.")
        }

        let timeStr = next.date.formatted(.dateTime.hour().minute())
        return .result(dialog: "Next up: \(next.peptide.abbreviation) \(next.dose) at \(timeStr)")
    }
}

// MARK: - Compliance Intent

struct ComplianceIntent: AppIntent {
    static let title: LocalizedStringResource = "How's My Compliance?"
    static let description = IntentDescription("Shows your current compliance stats")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = await IntentDataSnapshot.load()
        let calendar = Calendar.current
        let last7Days = snapshot.entries.filter {
            guard let cutoff = calendar.date(byAdding: .day, value: -7, to: Date()) else { return false }
            return $0.date >= cutoff
        }
        guard !last7Days.isEmpty else {
            return .result(dialog: "No recent data. Start logging doses in PeptideX.")
        }

        let compliance = Double(last7Days.filter(\.completed).count) / Double(last7Days.count)
        let percentage = Int(compliance * 100)
        return .result(dialog: "Your 7-day compliance is \(percentage)%. Keep it up!")
    }
}

// MARK: - Log Dose Intent

struct LogDoseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log My Dose"
    static let description = IntentDescription("Marks your next scheduled dose as taken")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: "Opening PeptideX...")
    }
}

// MARK: - Log Specific Peptide Intent (parameterized)

/// Parameterized variant — "Log my BPC-157" via Siri. Takes a peptide
/// name string and disambiguates against the active stack so the user
/// doesn't have to repeat the full name. Routes through the app on
/// success so the user can confirm the dose details before persisting.
struct LogSpecificPeptideIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Peptide"
    static let description = IntentDescription("Logs a dose for a specific peptide in your active stack")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Peptide", description: "Compound abbreviation or name")
    var peptideName: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = await IntentDataSnapshot.load()
        let needle = peptideName.lowercased()
        let active = snapshot.protocols.filter { $0.status == .active }
        let candidates: [Peptide] = active
            .flatMap(\.peptides)
            .filter { $0.name.lowercased().contains(needle) || $0.abbreviation.lowercased().contains(needle) }
        guard let match = candidates.first else {
            return .result(dialog: "Couldn't find \(peptideName) in your active stack.")
        }
        return .result(dialog: "Opening \(match.abbreviation) so you can confirm the dose.")
    }
}

// MARK: - Today Macros Intent

/// "What are my macros today?" — surfaces the calorie + protein totals
/// from the Lifestyle tab's daily consumption bucket so the user can
/// check progress without opening the app.
struct TodayMacrosIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's Macros"
    static let description = IntentDescription("Shows your calories and protein eaten today")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = await IntentDataSnapshot.load()
        guard let consumption = snapshot.todaysConsumption else {
            return .result(dialog: "No meals logged today. Open PeptideX to scan one.")
        }
        let summary = "Today: \(consumption.caloriesKcal) kcal, \(consumption.proteinG) g protein."
        return .result(dialog: IntentDialog(stringLiteral: summary))
    }
}

// MARK: - Snapshot

/// Reads protocols/entries from the SwiftData store on the main actor so AppIntents
/// see the same data the live app does. Falls back to legacy JSON files only when
/// SwiftData is empty (pre-migration), to maintain compatibility for users who haven't
/// reopened the app after upgrading.
private struct IntentDataSnapshot {
    let protocols: [PeptideProtocol]
    let entries: [ProtocolEntry]
    let todaysConsumption: DailyConsumption?

    @MainActor
    static func load() -> IntentDataSnapshot {
        let repo = SwiftDataRepository.shared
        let protocols = repo.loadProtocols()
        let entries = repo.loadEntries()
        let profile = PersistenceService.shared.loadProfile()
        let key = todayConsumptionKey()
        let consumption = profile?.dailyConsumption[key]

        if !protocols.isEmpty || !entries.isEmpty {
            return IntentDataSnapshot(
                protocols: protocols,
                entries: entries,
                todaysConsumption: consumption
            )
        }

        // Fallback: data is still in legacy JSON (migration hasn't run yet).
        let persistence = PersistenceService.shared
        return IntentDataSnapshot(
            protocols: persistence.loadProtocols() ?? [],
            entries: persistence.loadEntries() ?? [],
            todaysConsumption: consumption
        )
    }

    /// Mirrors DataStore.consumptionKey — pin to the local timezone so a
    /// late-night Siri query asks about the user's wall-clock today, not
    /// UTC's.
    private static func todayConsumptionKey() -> String {
        let day = Calendar.current.startOfDay(for: Date())
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = Calendar.current.timeZone
        return formatter.string(from: day)
    }
}

// MARK: - App Shortcuts Provider

struct PeptideShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextDoseIntent(),
            phrases: [
                "What's my next dose in \(.applicationName)",
                "Next peptide dose in \(.applicationName)",
                "When is my next dose \(.applicationName)",
            ],
            shortTitle: "Next Dose",
            systemImageName: "syringe.fill"
        )
        AppShortcut(
            intent: ComplianceIntent(),
            phrases: [
                "How's my compliance in \(.applicationName)",
                "Check my peptide compliance \(.applicationName)",
                "My compliance stats \(.applicationName)",
            ],
            shortTitle: "Compliance",
            systemImageName: "chart.bar.fill"
        )
        AppShortcut(
            intent: LogDoseIntent(),
            phrases: [
                "Log my dose in \(.applicationName)",
                "Mark dose as taken \(.applicationName)",
            ],
            shortTitle: "Log Dose",
            systemImageName: "checkmark.circle.fill"
        )
        AppShortcut(
            intent: LogSpecificPeptideIntent(),
            phrases: [
                "Log my \(\.$peptideName) in \(.applicationName)",
                "Take \(\.$peptideName) in \(.applicationName)",
            ],
            shortTitle: "Log Specific Peptide",
            systemImageName: "syringe"
        )
        AppShortcut(
            intent: TodayMacrosIntent(),
            phrases: [
                "What are my macros today in \(.applicationName)",
                "How many calories have I eaten today in \(.applicationName)",
                "Today's protein in \(.applicationName)",
            ],
            shortTitle: "Today's Macros",
            systemImageName: "fork.knife.circle.fill"
        )
    }
}
