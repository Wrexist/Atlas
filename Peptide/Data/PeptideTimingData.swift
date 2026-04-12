import Foundation

/// Temporal knowledge base for the recommendation engine.
/// Covers optimal timing windows, cycling protocols, desensitization risks, and seasonal context.
enum PeptideTimingData {

    // MARK: - Timing Windows

    enum TimingWindow: String, CaseIterable {
        case morningFasted = "Morning (fasted)"
        case morningWithFood = "Morning (with food)"
        case preworkout = "Pre-workout"
        case postWorkout = "Post-workout"
        case evening = "Evening"
        case preBed = "Before bed"
        case anyTime = "Any time"
    }

    struct PeptideTiming {
        let abbreviation: String
        let preferredWindows: [TimingWindow]
        let avoidWith: [String]
        let notes: String
    }

    static let timingRecommendations: [String: PeptideTiming] = {
        let entries: [PeptideTiming] = [
            // GH Secretagogues — fasted, pre-bed for natural GH pulse synergy
            PeptideTiming(abbreviation: "CJC-1295 DAC", preferredWindows: [.preBed, .morningFasted], avoidWith: [], notes: "Best before bed on empty stomach for synergy with natural GH pulse"),
            PeptideTiming(abbreviation: "Ipamorelin", preferredWindows: [.preBed, .morningFasted], avoidWith: [], notes: "Empty stomach required. 30 min before bed or upon waking"),
            PeptideTiming(abbreviation: "Mod GRF 1-29", preferredWindows: [.preBed, .morningFasted], avoidWith: [], notes: "Combine with Ipamorelin at same injection time"),
            PeptideTiming(abbreviation: "Sermorelin", preferredWindows: [.preBed], avoidWith: [], notes: "Pre-bed dosing mimics natural nocturnal GH secretion"),
            PeptideTiming(abbreviation: "Tesamorelin", preferredWindows: [.preBed, .morningFasted], avoidWith: [], notes: "Fasted state prevents blunting of GH release by insulin"),
            PeptideTiming(abbreviation: "GHRP-2", preferredWindows: [.preBed, .morningFasted], avoidWith: [], notes: "Fasted — carbs/fats blunt GH release. Stimulates appetite"),
            PeptideTiming(abbreviation: "GHRP-6", preferredWindows: [.preBed, .morningFasted], avoidWith: [], notes: "Strong appetite stimulation — time around meals if desired"),
            PeptideTiming(abbreviation: "Hexarelin", preferredWindows: [.preBed, .morningFasted], avoidWith: [], notes: "Short-term use. Fasted for maximal GH pulse"),
            PeptideTiming(abbreviation: "MK-677", preferredWindows: [.preBed, .evening], avoidWith: [], notes: "Oral. Evening dosing reduces daytime hunger and insulin spike impact"),

            // Recovery — near injury site, morning or post-workout
            PeptideTiming(abbreviation: "BPC-157", preferredWindows: [.morningFasted, .postWorkout], avoidWith: [], notes: "Inject near injury site if applicable. Stable peptide"),
            PeptideTiming(abbreviation: "TB-500", preferredWindows: [.anyTime], avoidWith: [], notes: "Systemic action — injection site less important than BPC-157"),
            PeptideTiming(abbreviation: "GHK-Cu", preferredWindows: [.morningFasted, .preBed], avoidWith: [], notes: "Flexible timing. Topical application for skin; subcutaneous for systemic"),
            PeptideTiming(abbreviation: "PDA", preferredWindows: [.morningFasted, .postWorkout], avoidWith: [], notes: "Similar timing to BPC-157 for tissue repair applications"),

            // Cognitive — morning for daytime cognitive benefit
            PeptideTiming(abbreviation: "Semax", preferredWindows: [.morningFasted, .morningWithFood], avoidWith: ["Selank"], notes: "Intranasal. Separate from Selank by 15+ min if using both"),
            PeptideTiming(abbreviation: "Selank", preferredWindows: [.morningFasted, .evening], avoidWith: ["Semax"], notes: "Intranasal. Evening use provides anxiolytic benefit for sleep"),
            PeptideTiming(abbreviation: "NA-Semax", preferredWindows: [.morningFasted], avoidWith: [], notes: "Acetylated form — longer lasting. Morning for all-day cognition"),
            PeptideTiming(abbreviation: "Dihexa", preferredWindows: [.morningFasted], avoidWith: [], notes: "Oral or intranasal. Morning for cognitive enhancement throughout the day"),
            PeptideTiming(abbreviation: "PE-22-28", preferredWindows: [.morningFasted], avoidWith: [], notes: "Morning dosing for daytime neurotrophic effects"),
            PeptideTiming(abbreviation: "P21", preferredWindows: [.morningFasted], avoidWith: [], notes: "Morning for BDNF-driven neuroplasticity support"),

            // Metabolic — fasted for fat metabolism
            PeptideTiming(abbreviation: "AOD-9604", preferredWindows: [.morningFasted], avoidWith: [], notes: "Must be fasted. Do not eat for 30 min after injection"),
            PeptideTiming(abbreviation: "Semaglutide", preferredWindows: [.anyTime], avoidWith: [], notes: "Once weekly, any time. Consistency matters more than timing"),
            PeptideTiming(abbreviation: "Tirzepatide", preferredWindows: [.anyTime], avoidWith: [], notes: "Once weekly. Pick a consistent day"),
            PeptideTiming(abbreviation: "Retatrutide", preferredWindows: [.anyTime], avoidWith: [], notes: "Once weekly injection"),
            PeptideTiming(abbreviation: "Liraglutide", preferredWindows: [.morningFasted], avoidWith: [], notes: "Daily injection. Morning dosing may help with daytime appetite control"),

            // Anti-Aging
            PeptideTiming(abbreviation: "Epitalon", preferredWindows: [.preBed], avoidWith: [], notes: "Evening/pre-bed to support melatonin regulation and circadian rhythm"),
            PeptideTiming(abbreviation: "NAD+", preferredWindows: [.morningFasted], avoidWith: [], notes: "Morning for cellular energy support throughout the day"),

            // Immune — morning or any time
            PeptideTiming(abbreviation: "TA1", preferredWindows: [.morningFasted, .anyTime], avoidWith: [], notes: "Subcutaneous. Flexible timing for immune modulation"),
            PeptideTiming(abbreviation: "LL-37", preferredWindows: [.morningFasted], avoidWith: [], notes: "Morning dosing. Direct antimicrobial peptide"),
            PeptideTiming(abbreviation: "KPV", preferredWindows: [.morningFasted, .preBed], avoidWith: [], notes: "Oral or subcutaneous. For gut: take before meals"),
            PeptideTiming(abbreviation: "Thymulin", preferredWindows: [.morningFasted], avoidWith: [], notes: "Morning for immune system priming"),

            // IGF-1 — peri-workout
            PeptideTiming(abbreviation: "IGF-1 LR3", preferredWindows: [.postWorkout, .morningFasted], avoidWith: [], notes: "Post-workout for localized muscle growth. Monitor blood sugar"),
            PeptideTiming(abbreviation: "IGF-1 DES", preferredWindows: [.preworkout, .postWorkout], avoidWith: [], notes: "Very short-acting — use peri-workout for acute pulses"),
            PeptideTiming(abbreviation: "MGF", preferredWindows: [.postWorkout], avoidWith: [], notes: "Immediately post-workout for mechano-growth factor response"),
            PeptideTiming(abbreviation: "PEG-MGF", preferredWindows: [.postWorkout], avoidWith: [], notes: "PEGylated for extended half-life. Post-workout on non-IGF days"),

            // Other
            PeptideTiming(abbreviation: "FST-344", preferredWindows: [.morningFasted], avoidWith: [], notes: "Morning dosing for myostatin inhibition throughout the day"),
            PeptideTiming(abbreviation: "KP-10", preferredWindows: [.morningFasted, .preBed], avoidWith: [], notes: "Pulsatile dosing preferred. Morning or pre-bed for hormonal axis"),
        ]
        return Dictionary(entries.map { ($0.abbreviation, $0) }, uniquingKeysWith: { _, new in new })
    }()

    // MARK: - Cycling Protocols

    struct CycleProtocol {
        let abbreviation: String
        let onWeeks: Int
        let offWeeks: Int
        let reason: String
        let transitionSuggestions: [String]
    }

    static let cycleProtocols: [String: CycleProtocol] = {
        let entries: [CycleProtocol] = [
            // GH Secretagogues
            CycleProtocol(abbreviation: "CJC-1295 DAC", onWeeks: 8, offWeeks: 4, reason: "Prevents pituitary desensitization to GHRH signaling", transitionSuggestions: ["Mod GRF 1-29", "Sermorelin"]),
            CycleProtocol(abbreviation: "Ipamorelin", onWeeks: 8, offWeeks: 4, reason: "GHS-R receptor sensitivity maintenance", transitionSuggestions: ["GHRP-2", "Sermorelin"]),
            CycleProtocol(abbreviation: "Mod GRF 1-29", onWeeks: 8, offWeeks: 4, reason: "GHRH receptor recovery period", transitionSuggestions: ["CJC-1295 DAC", "Sermorelin"]),
            CycleProtocol(abbreviation: "Sermorelin", onWeeks: 12, offWeeks: 4, reason: "Milder GHRH analog but still benefits from cycling", transitionSuggestions: ["CJC-1295 DAC"]),
            CycleProtocol(abbreviation: "Tesamorelin", onWeeks: 12, offWeeks: 4, reason: "Allow assessment of visceral fat reduction progress", transitionSuggestions: ["AOD-9604"]),
            CycleProtocol(abbreviation: "GHRP-2", onWeeks: 8, offWeeks: 4, reason: "GHS-R desensitization and cortisol/prolactin elevation with prolonged use", transitionSuggestions: ["Ipamorelin"]),
            CycleProtocol(abbreviation: "GHRP-6", onWeeks: 8, offWeeks: 4, reason: "Same GHS-R desensitization concern, plus appetite stimulation tolerance", transitionSuggestions: ["Ipamorelin"]),
            CycleProtocol(abbreviation: "Hexarelin", onWeeks: 4, offWeeks: 4, reason: "Strongest GHS-R agonist — fastest receptor desensitization", transitionSuggestions: ["Ipamorelin", "GHRP-2"]),
            CycleProtocol(abbreviation: "MK-677", onWeeks: 8, offWeeks: 4, reason: "Prolonged oral GHS-R activation leads to receptor downregulation and insulin resistance", transitionSuggestions: ["Ipamorelin"]),

            // Recovery
            CycleProtocol(abbreviation: "BPC-157", onWeeks: 6, offWeeks: 2, reason: "Allow assessment of healing progress; no known receptor desensitization", transitionSuggestions: ["TB-500"]),
            CycleProtocol(abbreviation: "TB-500", onWeeks: 6, offWeeks: 4, reason: "Loading phase typically sufficient; maintain with lower frequency", transitionSuggestions: ["BPC-157"]),

            // Anti-Aging
            CycleProtocol(abbreviation: "Epitalon", onWeeks: 3, offWeeks: 12, reason: "Telomerase activation persists well after cessation; short courses are standard", transitionSuggestions: ["GHK-Cu"]),
            CycleProtocol(abbreviation: "GHK-Cu", onWeeks: 8, offWeeks: 4, reason: "Allow collagen remodeling to stabilize between courses", transitionSuggestions: ["Epitalon"]),

            // Metabolic
            CycleProtocol(abbreviation: "Semaglutide", onWeeks: 16, offWeeks: 4, reason: "Assess metabolic response and prevent GI tolerance issues", transitionSuggestions: ["AOD-9604", "Tirzepatide"]),
            CycleProtocol(abbreviation: "AOD-9604", onWeeks: 12, offWeeks: 4, reason: "Evaluate fat loss progress and prevent metabolic adaptation", transitionSuggestions: ["Tesamorelin"]),

            // Cognitive
            CycleProtocol(abbreviation: "Semax", onWeeks: 4, offWeeks: 2, reason: "BDNF upregulation persists during off-period; prevents receptor adaptation", transitionSuggestions: ["Selank", "NA-Semax"]),
            CycleProtocol(abbreviation: "Selank", onWeeks: 4, offWeeks: 2, reason: "GABA receptor modulation benefits from periodic reset", transitionSuggestions: ["Semax"]),
            CycleProtocol(abbreviation: "Dihexa", onWeeks: 4, offWeeks: 4, reason: "Potent HGF mimetic — conservative cycling recommended", transitionSuggestions: ["Semax", "PE-22-28"]),

            // IGF-1
            CycleProtocol(abbreviation: "IGF-1 LR3", onWeeks: 4, offWeeks: 4, reason: "Prolonged IGF-1 elevation risks insulin resistance and organ growth", transitionSuggestions: ["MGF", "PEG-MGF"]),

            // Immune
            CycleProtocol(abbreviation: "TA1", onWeeks: 8, offWeeks: 4, reason: "T-cell maturation continues after cessation", transitionSuggestions: ["LL-37", "KPV"]),
        ]
        return Dictionary(entries.map { ($0.abbreviation, $0) }, uniquingKeysWith: { _, new in new })
    }()

    // MARK: - Desensitization Risk

    struct DesensitizationInfo {
        let abbreviation: String
        let receptor: String
        let riskOnsetWeeks: Int
        let description: String
    }

    static let desensitizationRisks: [String: DesensitizationInfo] = [
        "Ipamorelin": DesensitizationInfo(abbreviation: "Ipamorelin", receptor: "GHS-R1a", riskOnsetWeeks: 8, description: "Ghrelin receptor downregulation reduces GH response"),
        "GHRP-2": DesensitizationInfo(abbreviation: "GHRP-2", receptor: "GHS-R1a", riskOnsetWeeks: 6, description: "Ghrelin receptor downregulation with increasing cortisol/prolactin"),
        "GHRP-6": DesensitizationInfo(abbreviation: "GHRP-6", receptor: "GHS-R1a", riskOnsetWeeks: 6, description: "Ghrelin receptor downregulation with appetite tolerance"),
        "Hexarelin": DesensitizationInfo(abbreviation: "Hexarelin", receptor: "GHS-R1a", riskOnsetWeeks: 4, description: "Strongest GHS-R agonist — fastest desensitization onset"),
        "MK-677": DesensitizationInfo(abbreviation: "MK-677", receptor: "GHS-R1a", riskOnsetWeeks: 8, description: "Continuous oral GHS-R activation leads to progressive downregulation"),
    ]

    // MARK: - Seasonal Boosts

    static let seasonalBoosts: [PeptideCategory: Set<Int>] = [
        .immune: [9, 10, 11, 12, 1, 2],
        .metabolic: [3, 4, 5, 6],
        .recovery: [5, 6, 7, 8],
        .antiAging: [10, 11, 12, 1, 2, 3],
    ]

    // MARK: - Well-Known Peptides (for experience-level scoring)

    /// Peptides that appear in validated stacks and have the most research backing.
    /// Recommended first for beginners building their initial stack.
    static let wellKnownPeptides: Set<String> = [
        "BPC-157", "TB-500", "GHK-Cu",
        "CJC-1295 DAC", "Ipamorelin", "Mod GRF 1-29", "Sermorelin",
        "Semax", "Selank",
        "TA1", "LL-37", "KPV",
        "AOD-9604", "Semaglutide",
        "Epitalon",
    ]
}
