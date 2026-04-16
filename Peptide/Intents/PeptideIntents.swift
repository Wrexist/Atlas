import AppIntents
import Foundation

// MARK: - Next Dose Intent

struct NextDoseIntent: AppIntent {
    static let title: LocalizedStringResource = "What's My Next Dose?"
    static let description = IntentDescription("Shows your next scheduled peptide dose")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let persistence = PersistenceService.shared
        guard let protocols = persistence.loadProtocols(),
              let entries = persistence.loadEntries() else {
            return .result(dialog: "No protocols found. Open PeptideX to get started.")
        }

        let calendar = Calendar.current
        let now = Date()
        let activeIds = Set(protocols.filter { $0.status == .active }.map(\.id))
        let todayEntries = entries
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
        let persistence = PersistenceService.shared
        guard let entries = persistence.loadEntries() else {
            return .result(dialog: "No data found. Open PeptideX to start tracking.")
        }

        let calendar = Calendar.current
        let last7Days = entries.filter {
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
    }
}
