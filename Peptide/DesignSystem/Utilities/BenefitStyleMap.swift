import SwiftUI

enum BenefitStyleMap {
    struct Style {
        let icon: String
        let color: Color
    }

    // Ordering matters: more-specific keywords must precede shorter
    // substrings they contain (e.g. "Tissue Repair" before "Repair").
    // The first match wins via localizedCaseInsensitiveContains.
    // Colours come from the category so they follow its light-mode inks.
    static let mappings: [(keyword: String, icon: String, category: PeptideCategory)] = [
        // Recovery (blue)
        ("Tissue Repair", "wrench.and.screwdriver.fill", .recovery),
        ("Tissue Regeneration", "arrow.triangle.2.circlepath", .recovery),
        ("Cartilage Repair", "figure.walk", .recovery),
        ("Cardiac Repair", "heart.fill", .immune),
        ("Skin Repair", "hand.raised.fingers.spread.fill", .antiAging),
        ("DNA Repair", "staroflife.fill", .immune),
        ("Repair", "wrench.and.screwdriver.fill", .recovery),
        ("Regeneration", "arrow.triangle.2.circlepath", .recovery),
        ("Healing", "cross.circle.fill", .recovery),
        ("Wound", "cross.circle.fill", .recovery),
        ("Recovery", "arrow.counterclockwise", .recovery),
        ("Joint", "figure.walk", .recovery),
        ("Tendon", "bandage.fill", .recovery),
        ("Flexibility", "figure.cooldown", .recovery),
        ("Hair", "comb.fill", .recovery),

        // Growth (green)
        ("Gut", "leaf.fill", .growth),
        ("Protein Synthesis", "atom", .growth),
        ("Cell Proliferation", "circle.grid.3x3.fill", .growth),
        ("Anti-Inflammatory", "leaf.fill", .growth),
        ("Inflammation", "leaf.fill", .growth),
        ("Muscle", "figure.strengthtraining.traditional", .growth),
        ("Growth", "arrow.up.right", .growth),
        ("GH Release", "arrow.up.circle.fill", .growth),
        ("GH Stimulation", "arrow.up.circle.fill", .growth),

        // Metabolic (orange)
        ("Visceral Fat", "flame.fill", .metabolic),
        ("Fat Loss", "flame.fill", .metabolic),
        ("Fat Metabolism", "flame.fill", .metabolic),
        ("Fat Reduction", "flame.fill", .metabolic),
        ("Lipolysis", "flame.fill", .metabolic),
        ("Metabolic", "bolt.fill", .metabolic),
        ("Metabolism", "bolt.fill", .metabolic),
        ("Body Composition", "scalemass.fill", .metabolic),
        ("Weight", "scalemass.fill", .metabolic),
        ("IGF-1", "arrow.up.right", .metabolic),

        // Immune (red)
        ("T-Cell", "shield.checkered", .immune),
        ("Anti-Viral", "shield.lefthalf.filled", .immune),
        ("Anti-Biofilm", "shield.lefthalf.filled", .immune),
        ("Antimicrobial", "shield.lefthalf.filled", .immune),
        ("Vaccine", "cross.vial.fill", .immune),
        ("Cancer", "staroflife.fill", .immune),
        ("Immune", "shield.checkered", .immune),
        ("Cardiac", "heart.fill", .immune),
        ("Cardiovascular", "heart.fill", .immune),
        ("Heart", "heart.fill", .immune),

        // Anti-Aging (gold)
        ("Deep Sleep", "moon.zzz.fill", .antiAging),
        ("Sleep", "moon.fill", .antiAging),
        ("Collagen", "sparkle", .antiAging),
        ("Anti-Aging", "hourglass", .antiAging),
        ("Longevity", "infinity", .antiAging),
        ("Telomere", "infinity", .antiAging),
        ("Melatonin", "moon.fill", .antiAging),
        ("Skin", "hand.raised.fingers.spread.fill", .antiAging),
        ("Mood", "sun.max.fill", .antiAging),

        // Cognitive (purple)
        ("Neurogenesis", "brain.head.profile", .cognitive),
        ("Synaptogenesis", "brain.head.profile", .cognitive),
        ("Neuroprotection", "brain.head.profile", .cognitive),
        ("Neuroplasticity", "brain.head.profile", .cognitive),
        ("Cognitive", "brain.head.profile", .cognitive),
        ("BDNF", "brain", .cognitive),
        ("Memory", "brain", .cognitive),
        ("Focus", "eye.fill", .cognitive),
        ("Anxiety", "wind", .cognitive),
        ("Stress", "wind", .cognitive),
    ]

    static func style(for benefit: String, fallbackColor: Color) -> Style {
        for mapping in mappings where benefit.localizedCaseInsensitiveContains(mapping.keyword) {
            return Style(icon: mapping.icon, color: mapping.category.color)
        }
        return Style(icon: "checkmark.seal.fill", color: fallbackColor)
    }
}
