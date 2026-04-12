import Foundation

/// Research-backed peptide compatibility knowledge base.
/// Sources: PubMed, clinical guides, peptide therapy literature.
/// This data enhances the recommendation engine with validated stacking
/// knowledge and interaction warnings beyond what commonStacks provides.
enum PeptideCompatibilityData {

    // MARK: - Validated Stacks

    /// Clinically or research-validated peptide combinations with known synergy mechanisms.
    struct ValidatedStack {
        let name: String
        let peptideAbbreviations: [String]
        let goal: String
        let synergy: String
        let notes: String
    }

    static let validatedStacks: [ValidatedStack] = [
        // Recovery
        ValidatedStack(
            name: "Wolverine Stack",
            peptideAbbreviations: ["BPC-157", "TB-500"],
            goal: "Tissue repair & recovery",
            synergy: "BPC-157 upregulates VEGF and nitric oxide for blood vessel formation while TB-500 regulates actin for cell migration. Together they address complementary stages of the healing cascade.",
            notes: "Most studied multi-peptide combination in tissue repair research."
        ),
        ValidatedStack(
            name: "Extended Wolverine",
            peptideAbbreviations: ["BPC-157", "TB-500", "GHK-Cu"],
            goal: "Full-spectrum tissue repair",
            synergy: "Adds GHK-Cu's collagen synthesis (up to 70% increase in Type I/III collagen) to the Wolverine stack. GHK-Cu provides the copper cofactor for lysyl oxidase cross-linking that neither BPC-157 nor TB-500 directly addresses.",
            notes: "Three complementary mechanisms with zero receptor overlap."
        ),
        // Growth Hormone
        ValidatedStack(
            name: "GH Pulse Stack",
            peptideAbbreviations: ["CJC-1295 DAC", "Ipamorelin"],
            goal: "Growth hormone optimization",
            synergy: "CJC-1295 (GHRH analog) activates cAMP/PKA via the GHRH receptor while Ipamorelin (GHS-R agonist) activates phospholipase C via the ghrelin receptor. Different receptors produce synergistic GH release 2-3x greater than either alone.",
            notes: "Gold standard GH stack. Ipamorelin is selective — doesn't elevate cortisol or prolactin unlike GHRP-2/6."
        ),
        ValidatedStack(
            name: "GH Pulse Stack (non-DAC)",
            peptideAbbreviations: ["Mod GRF 1-29", "Ipamorelin"],
            goal: "Pulsatile growth hormone release",
            synergy: "Same GHRH+GHRP synergy mechanism as CJC-1295/Ipamorelin but with shorter-acting Mod GRF for more natural pulsatile GH release patterns.",
            notes: "Preferred for mimicking natural GH rhythm. Often dosed before bed."
        ),
        ValidatedStack(
            name: "GH + Recovery",
            peptideAbbreviations: ["CJC-1295 DAC", "Ipamorelin", "BPC-157"],
            goal: "Growth hormone + injury recovery",
            synergy: "GH elevation from CJC/Ipamorelin enhances protein synthesis while BPC-157 directs repair signaling to injured tissue. GH supports systemic anabolism; BPC-157 provides targeted tissue protection.",
            notes: "Common clinical protocol for athletes recovering from injuries."
        ),
        // Cognitive
        ValidatedStack(
            name: "Cognitive Enhancement",
            peptideAbbreviations: ["Semax", "Selank"],
            goal: "Focus, memory, and calm alertness",
            synergy: "Semax upregulates BDNF and enhances dopaminergic/serotonergic signaling for focus and memory. Selank modulates GABA receptors for anxiolysis without drowsiness. Together they address the stress-cognition axis — Selank buffers stress while Semax drives neural performance.",
            notes: "Both are intranasal. Developed at the Russian Academy of Sciences with extensive clinical use in Russia."
        ),
        // Immune
        ValidatedStack(
            name: "Immune Defense Stack",
            peptideAbbreviations: ["TA1", "LL-37", "KPV"],
            goal: "Comprehensive immune support",
            synergy: "TA1 boosts adaptive immunity (T-cell maturation). LL-37 provides direct innate antimicrobial action (disrupts bacterial/viral membranes). KPV suppresses excessive inflammation via NF-κB inhibition. Three layers of defense with minimal overlap.",
            notes: "Each peptide targets a different arm of the immune system."
        ),
        ValidatedStack(
            name: "Immune + Gut Healing",
            peptideAbbreviations: ["TA1", "BPC-157", "KPV"],
            goal: "Gut immune restoration",
            synergy: "BPC-157 protects and repairs GI mucosal lining. KPV reduces intestinal inflammation. TA1 supports systemic immune function. Addresses gut-immune axis from mucosal barrier, inflammation, and systemic immunity simultaneously.",
            notes: "Relevant for inflammatory bowel conditions."
        ),
        // Metabolic
        ValidatedStack(
            name: "Metabolic + Body Composition",
            peptideAbbreviations: ["AOD-9604", "CJC-1295 DAC", "Ipamorelin"],
            goal: "Fat loss while preserving muscle",
            synergy: "AOD-9604 directly enhances fat metabolism via beta-3 adrenergic receptors without raising IGF-1 or insulin. CJC-1295/Ipamorelin elevate GH for lean mass preservation. Different pathways — AOD targets adipocytes directly while GH peptides work systemically.",
            notes: "AOD-9604 retains lipolytic properties of GH without growth effects."
        ),
        // Anti-Aging
        ValidatedStack(
            name: "Longevity Stack",
            peptideAbbreviations: ["Epitalon", "GHK-Cu", "BPC-157"],
            goal: "Anti-aging and cellular renewal",
            synergy: "Epitalon activates telomerase for telomere maintenance. GHK-Cu stimulates collagen/elastin synthesis and has broad gene-resetting activity. BPC-157 provides systemic cytoprotection. Addresses aging at genetic (telomeres), structural (collagen), and protective levels.",
            notes: "Epitalon is typically cycled in 10-20 day courses."
        ),
    ]

    // MARK: - Known Interactions (Avoid)

    struct Interaction {
        let peptideA: String
        let peptideB: String
        let severity: Severity
        let reason: String
        let recommendation: String

        enum Severity: String {
            case danger = "danger"
            case caution = "caution"
        }
    }

    static let knownInteractions: [Interaction] = [
        // GHS-R receptor redundancy (same receptor = desensitization risk)
        Interaction(
            peptideA: "Ipamorelin", peptideB: "GHRP-6",
            severity: .caution,
            reason: "Both activate the same GHS-R1a receptor. Combining saturates the receptor without additive GH benefit and amplifies side effects (GHRP-6 elevates cortisol and stimulates appetite).",
            recommendation: "Use Ipamorelin alone (selective, no cortisol/prolactin elevation) paired with a GHRH analog like CJC-1295 instead."
        ),
        Interaction(
            peptideA: "Ipamorelin", peptideB: "GHRP-2",
            severity: .caution,
            reason: "Both target GHS-R1a. GHRP-2 elevates ACTH to 350% of baseline and increases cortisol. Adding Ipamorelin provides no additional receptor-level benefit.",
            recommendation: "Choose one GHRP and pair it with a GHRH analog for true synergy."
        ),
        Interaction(
            peptideA: "Ipamorelin", peptideB: "Hexarelin",
            severity: .caution,
            reason: "Same GHS-R1a pathway. Hexarelin is the most potent GHRP but also raises cortisol and prolactin most aggressively. Combining with Ipamorelin creates receptor competition.",
            recommendation: "Use Hexarelin short-term if maximum GH pulse is needed, or Ipamorelin for cleaner long-term use."
        ),
        Interaction(
            peptideA: "GHRP-2", peptideB: "GHRP-6",
            severity: .caution,
            reason: "Both are GHS-R1a agonists with overlapping side effect profiles (appetite stimulation, cortisol elevation). Stacking amplifies these without proportional GH increase.",
            recommendation: "Pick one GHRP based on your tolerance for appetite stimulation (GHRP-6 stronger) and pair with CJC-1295."
        ),
        Interaction(
            peptideA: "GHRP-6", peptideB: "Hexarelin",
            severity: .caution,
            reason: "Redundant GHS-R1a activation. Both have unfavorable side effect profiles (cortisol, prolactin). Stacking worsens these without proportional efficacy gain.",
            recommendation: "Select the single best GHRP for your needs and combine with a GHRH analog."
        ),
        Interaction(
            peptideA: "GHRP-2", peptideB: "Hexarelin",
            severity: .caution,
            reason: "Same GHS-R1a receptor pathway. Both elevate cortisol and prolactin at effective GH-releasing doses.",
            recommendation: "Use one GHRP at optimal dose rather than two at sub-optimal doses."
        ),
        // GLP-1 agonist stacking
        Interaction(
            peptideA: "Semaglutide", peptideB: "Tirzepatide",
            severity: .caution,
            reason: "Both activate GLP-1 receptors. Tirzepatide also activates GIP. Combining amplifies GI side effects (nausea, vomiting, diarrhea) and increases hypoglycemia risk. No clinical evidence supports additive weight loss.",
            recommendation: "Use one GLP-1 agonist at a time. Tirzepatide typically produces greater weight loss than semaglutide alone."
        ),
        Interaction(
            peptideA: "Semaglutide", peptideB: "Liraglutide",
            severity: .caution,
            reason: "Both are GLP-1 receptor agonists with overlapping mechanisms. Semaglutide is longer-acting and generally more effective. No benefit to combining.",
            recommendation: "Use semaglutide (once weekly, superior efficacy) rather than combining with liraglutide (daily)."
        ),
        Interaction(
            peptideA: "Semaglutide", peptideB: "Retatrutide",
            severity: .caution,
            reason: "Retatrutide is a triple agonist (GLP-1/GIP/glucagon). Adding semaglutide doubles GLP-1 activation, amplifying GI side effects without demonstrated additive benefit.",
            recommendation: "Retatrutide as monotherapy produces up to 24% body weight reduction — adding semaglutide is unlikely to improve this."
        ),
        Interaction(
            peptideA: "Tirzepatide", peptideB: "Retatrutide",
            severity: .caution,
            reason: "Both activate GLP-1 and GIP receptors. Retatrutide adds glucagon agonism. Combining creates excessive incretin pathway stimulation.",
            recommendation: "Use one multi-agonist at a time. Retatrutide's triple action generally subsumes tirzepatide's dual action."
        ),
        // IGF-1 stacking
        Interaction(
            peptideA: "IGF-1 LR3", peptideB: "IGF-1 DES",
            severity: .caution,
            reason: "Both directly activate IGF-1 receptors. Stacking can lead to excessive IGF-1 signaling: joint pain, water retention, hypoglycemia, and theoretical organ growth risk.",
            recommendation: "Use one IGF-1 variant. IGF-1 LR3 for sustained effect or IGF-1 DES for acute peri-workout pulses."
        ),
    ]

    // MARK: - Receptor Pathway Classification

    struct PathwayGroup {
        let pathway: String
        let peptideAbbreviations: [String]
        let description: String
        let maxSafe: Int // recommended max peptides from this pathway
        let warningText: String
    }

    static let pathwayGroups: [PathwayGroup] = [
        PathwayGroup(
            pathway: "GHS-R1a (Ghrelin Receptor)",
            peptideAbbreviations: ["Ipamorelin", "GHRP-2", "GHRP-6", "Hexarelin", "MK-677"],
            description: "Growth hormone secretagogues acting on the ghrelin receptor",
            maxSafe: 1,
            warningText: "Use only one GHS-R agonist. Pair with a GHRH analog for synergy instead of stacking multiple GHRPs."
        ),
        PathwayGroup(
            pathway: "GHRH Receptor",
            peptideAbbreviations: ["CJC-1295 DAC", "Mod GRF 1-29", "Sermorelin", "Tesamorelin"],
            description: "Growth hormone releasing hormone analogs",
            maxSafe: 1,
            warningText: "One GHRH analog is sufficient. Pair with a GHS-R agonist (e.g. Ipamorelin) for synergistic GH release."
        ),
        PathwayGroup(
            pathway: "GLP-1 Receptor",
            peptideAbbreviations: ["Semaglutide", "Tirzepatide", "Retatrutide", "Liraglutide", "Dulaglutide", "Exenatide", "Lixisenatide", "Orforglipron", "Survodutide"],
            description: "Incretin mimetics for appetite and glucose regulation",
            maxSafe: 1,
            warningText: "Use only one GLP-1 agonist at a time. Stacking amplifies GI side effects without demonstrated additive efficacy."
        ),
        PathwayGroup(
            pathway: "IGF-1 Receptor",
            peptideAbbreviations: ["IGF-1 LR3", "IGF-1 DES", "MGF", "PEG-MGF"],
            description: "Insulin-like growth factor signaling for tissue growth",
            maxSafe: 1,
            warningText: "Use one IGF-1 variant at a time. Excessive IGF-1 signaling risks hypoglycemia, joint pain, and theoretical organ growth."
        ),
        PathwayGroup(
            pathway: "Tissue Repair (multi-pathway)",
            peptideAbbreviations: ["BPC-157", "TB-500", "TB-4", "GHK-Cu", "GHK", "PDA"],
            description: "Tissue repair peptides acting through different mechanisms (NO, actin, collagen)",
            maxSafe: 3,
            warningText: "These use different pathways and generally stack well. However, all promote angiogenesis — use caution with history of malignancy."
        ),
        PathwayGroup(
            pathway: "Cognitive/Nootropic",
            peptideAbbreviations: ["Semax", "NA-Semax", "NASA", "Selank", "NA-Selank", "Dihexa", "P21", "PE-22-28", "Noopept"],
            description: "Neuroprotective and cognitive-enhancing peptides",
            maxSafe: 3,
            warningText: "Semax + Selank is a validated synergy. Adding a third nootropic peptide may have diminishing returns."
        ),
        PathwayGroup(
            pathway: "Immune Modulation",
            peptideAbbreviations: ["TA1", "LL-37", "KPV", "Thymulin", "Thymogen", "Thymalin"],
            description: "Immune system modulators across innate and adaptive arms",
            maxSafe: 3,
            warningText: "These target different immune arms (adaptive, innate, anti-inflammatory) and generally complement each other."
        ),
    ]

    // MARK: - Angiogenesis Risk Peptides

    /// Peptides that promote blood vessel growth. Combining multiple in patients
    /// with cancer history poses theoretical tumor vascularization risk.
    static let angiogenicPeptides: Set<String> = [
        "BPC-157", "TB-500", "TB-4", "GHK-Cu", "GHK", "PDA",
        "IGF-1 LR3", "IGF-1 DES", "MGF", "PEG-MGF"
    ]

    // MARK: - Lookup Helpers

    /// Find a known interaction between two peptides (by abbreviation).
    static func findInteraction(between a: String, and b: String) -> Interaction? {
        knownInteractions.first { interaction in
            (interaction.peptideA == a && interaction.peptideB == b) ||
            (interaction.peptideA == b && interaction.peptideB == a)
        }
    }

    /// Find all pathway groups a peptide belongs to.
    static func pathways(for abbreviation: String) -> [PathwayGroup] {
        pathwayGroups.filter { $0.peptideAbbreviations.contains(abbreviation) }
    }

    /// Find validated stacks that include a given peptide.
    static func validatedStacks(containing abbreviation: String) -> [ValidatedStack] {
        validatedStacks.filter { $0.peptideAbbreviations.contains(abbreviation) }
    }
}
