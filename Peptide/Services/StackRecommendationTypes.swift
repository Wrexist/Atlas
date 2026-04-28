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
                    : names.prefix(2).joined(separator: ", ") + " +\(names.count - 2) more"
                return "Pairs well with \(display)"
            case .goalMatch(let goal):
                return "Matches your \"\(goal)\" goal"
            case .categorySynergy(let desc):
                return desc
            case .sharedBenefits(let count):
                return "Shares \(count) benefits with your stack"
            case .validatedStack(let name, _):
                return "Part of \(name) — research-backed combination"
            case .timingComplement(let desc):
                return desc
            case .complianceBoost(let category):
                return "You're highly compliant with \(category) peptides"
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
            case .low: return "Exploratory"
            case .medium: return "Suggested"
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
        let id = UUID()
        let severity: Severity
        let title: String
        let detail: String
        let suggestion: String
        let peptides: [String]
        let icon: String

        enum Severity: Comparable {
            case info, caution, danger
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
