import Foundation

// Model types for the StackRecommendationEngine. Kept in their own file so the
// algorithm in StackRecommendationEngine.swift stays focused on business logic.

extension StackRecommendationEngine {

    enum RecommendationReason {
        case commonStack(pairsWith: [String])
        case goalMatch(goal: String)
        case categorySynergy(description: String)
        case sharedBenefits(count: Int)
        case validatedStack(name: String, synergy: String)
        case timingComplement(description: String)
        case complianceBoost(category: String)
        case routeDiversity(route: String)
        case halfLifeComplement(description: String)
        case seasonalRelevance(description: String)

        var icon: String {
            switch self {
            case .commonStack: return "link"
            case .goalMatch: return "target"
            case .categorySynergy: return "sparkles"
            case .sharedBenefits: return "square.on.square"
            case .validatedStack: return "checkmark.seal.fill"
            case .timingComplement: return "clock"
            case .complianceBoost: return "checkmark.circle"
            case .routeDiversity: return "syringe"
            case .halfLifeComplement: return "waveform"
            case .seasonalRelevance: return "leaf"
            }
        }

        var text: String {
            switch self {
            case .commonStack(let names):
                let display = names.count <= 3
                    ? names.joined(separator: ", ")
                    : names.prefix(2).joined(separator: ", ") + String(localized: " +\(names.count - 2) more")
                return String(localized: "Pairs well with \(display)")
            case .goalMatch(let goal):
                return String(localized: "Matches your \"\(goal)\" goal")
            case .categorySynergy(let desc):
                return desc
            case .sharedBenefits(let count):
                return String(localized: "Shares \(count) benefits with your protocol")
            case .validatedStack(let name, _):
                return String(localized: "Part of the \(name) combination")
            case .timingComplement(let desc):
                return desc
            case .complianceBoost(let category):
                return String(localized: "You're highly compliant with \(category) peptides")
            case .routeDiversity(let route):
                return route
            case .halfLifeComplement(let desc):
                return desc
            case .seasonalRelevance(let desc):
                return desc
            }
        }
    }

    enum Confidence: Comparable {
        case low, medium, high

        var label: String {
            switch self {
            case .low: return String(localized: "Exploratory")
            case .medium: return String(localized: "Suggested")
            case .high: return "Research-backed"
            }
        }
    }

    struct Recommendation: Identifiable {
        let id: UUID
        let peptide: Peptide
        let score: Int
        let reasons: [RecommendationReason]
        let confidence: Confidence
    }

    struct Warning: Identifiable {
        let severity: Severity
        let title: String
        let detail: String
        let suggestion: String
        let peptides: [String]
        let icon: String
        var kind: Kind = .general

        enum Severity: Comparable {
            case info, caution, danger
        }

        /// What the warning is about, so the UI can pick a follow-up
        /// action without matching (localizable) title text.
        enum Kind {
            case general, cycleOverrun, desensitization, timingConflict, injectionBurden
        }

        /// Stable across renders and unique per warning: several kinds
        /// share one fixed title ("Known interaction") for different pairs.
        var id: String {
            "\(kind)|\(title)|\(peptides.sorted().joined(separator: "+"))"
        }

        /// Most severe first; ties break on content so the order (and the
        /// builder's top three) is the same on every launch.
        static func displayOrder(_ lhs: Warning, _ rhs: Warning) -> Bool {
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return lhs.id < rhs.id
        }
    }

    struct StackCompleteness {
        let score: Double
        let coveredGoals: [String]
        let missingCategories: [PeptideCategory]
        let suggestions: [String]
    }

    struct CycleTransition: Identifiable {
        let id = UUID()
        let peptideAbbreviation: String
        let weeksRemaining: Int
        let suggestedReplacements: [String]
        let reason: String
    }
}
