import SwiftUI

enum BenefitStyleMap {
    struct Style {
        let icon: String
        let color: Color
    }

    // Ordering matters: more-specific keywords must precede shorter
    // substrings they contain (e.g. "Tissue Repair" before "Repair").
    // The first match wins via localizedCaseInsensitiveContains.
    private static let mappings: [(keyword: String, icon: String, color: Color)] = [
        // Recovery (blue)
        ("Tissue Repair", "wrench.and.screwdriver.fill", Color(hex: 0x5B8FB9)),
        ("Tissue Regeneration", "arrow.triangle.2.circlepath", Color(hex: 0x5B8FB9)),
        ("Cartilage Repair", "figure.walk", Color(hex: 0x5B8FB9)),
        ("Cardiac Repair", "heart.fill", Color(hex: 0xCF7272)),
        ("Skin Repair", "hand.raised.fingers.spread.fill", Color(hex: 0xD4A844)),
        ("Repair", "wrench.and.screwdriver.fill", Color(hex: 0x5B8FB9)),
        ("Regeneration", "arrow.triangle.2.circlepath", Color(hex: 0x5B8FB9)),
        ("Healing", "cross.circle.fill", Color(hex: 0x5B8FB9)),
        ("Wound", "cross.circle.fill", Color(hex: 0x5B8FB9)),
        ("Recovery", "arrow.counterclockwise", Color(hex: 0x5B8FB9)),
        ("Joint", "figure.walk", Color(hex: 0x5B8FB9)),
        ("Tendon", "bandage.fill", Color(hex: 0x5B8FB9)),
        ("Flexibility", "figure.cooldown", Color(hex: 0x5B8FB9)),
        ("Hair", "comb.fill", Color(hex: 0x5B8FB9)),

        // Growth (green)
        ("Gut", "leaf.fill", Color(hex: 0x4A7C59)),
        ("Protein Synthesis", "atom", Color(hex: 0x4A7C59)),
        ("Cell Proliferation", "circle.grid.3x3.fill", Color(hex: 0x4A7C59)),
        ("Anti-Inflammatory", "leaf.fill", Color(hex: 0x4A7C59)),
        ("Inflammation", "leaf.fill", Color(hex: 0x4A7C59)),
        ("Muscle", "figure.strengthtraining.traditional", Color(hex: 0x4A7C59)),
        ("Growth", "arrow.up.right", Color(hex: 0x4A7C59)),
        ("GH Release", "arrow.up.circle.fill", Color(hex: 0x4A7C59)),
        ("GH Stimulation", "arrow.up.circle.fill", Color(hex: 0x4A7C59)),

        // Metabolic (orange)
        ("Visceral Fat", "flame.fill", Color(hex: 0xE88D4F)),
        ("Fat Loss", "flame.fill", Color(hex: 0xE88D4F)),
        ("Fat Metabolism", "flame.fill", Color(hex: 0xE88D4F)),
        ("Fat Reduction", "flame.fill", Color(hex: 0xE88D4F)),
        ("Lipolysis", "flame.fill", Color(hex: 0xE88D4F)),
        ("Metabolic", "bolt.fill", Color(hex: 0xE88D4F)),
        ("Metabolism", "bolt.fill", Color(hex: 0xE88D4F)),
        ("Body Composition", "scalemass.fill", Color(hex: 0xE88D4F)),
        ("Weight", "scalemass.fill", Color(hex: 0xE88D4F)),
        ("IGF-1", "arrow.up.right", Color(hex: 0xE88D4F)),

        // Immune (red)
        ("T-Cell", "shield.checkered", Color(hex: 0xCF7272)),
        ("Anti-Viral", "shield.lefthalf.filled", Color(hex: 0xCF7272)),
        ("Anti-Biofilm", "shield.lefthalf.filled", Color(hex: 0xCF7272)),
        ("Antimicrobial", "shield.lefthalf.filled", Color(hex: 0xCF7272)),
        ("Vaccine", "cross.vial.fill", Color(hex: 0xCF7272)),
        ("Cancer", "staroflife.fill", Color(hex: 0xCF7272)),
        ("DNA Repair", "staroflife.fill", Color(hex: 0xCF7272)),
        ("Immune", "shield.checkered", Color(hex: 0xCF7272)),
        ("Cardiac", "heart.fill", Color(hex: 0xCF7272)),
        ("Cardiovascular", "heart.fill", Color(hex: 0xCF7272)),
        ("Heart", "heart.fill", Color(hex: 0xCF7272)),

        // Anti-Aging (gold)
        ("Deep Sleep", "moon.zzz.fill", Color(hex: 0xD4A844)),
        ("Sleep", "moon.fill", Color(hex: 0xD4A844)),
        ("Collagen", "sparkle", Color(hex: 0xD4A844)),
        ("Anti-Aging", "hourglass", Color(hex: 0xD4A844)),
        ("Longevity", "infinity", Color(hex: 0xD4A844)),
        ("Telomere", "infinity", Color(hex: 0xD4A844)),
        ("Melatonin", "moon.fill", Color(hex: 0xD4A844)),
        ("Skin", "hand.raised.fingers.spread.fill", Color(hex: 0xD4A844)),
        ("Mood", "sun.max.fill", Color(hex: 0xD4A844)),

        // Cognitive (purple)
        ("Neurogenesis", "brain.head.profile", Color(hex: 0x9B72CF)),
        ("Synaptogenesis", "brain.head.profile", Color(hex: 0x9B72CF)),
        ("Neuroprotection", "brain.head.profile", Color(hex: 0x9B72CF)),
        ("Neuroplasticity", "brain.head.profile", Color(hex: 0x9B72CF)),
        ("Cognitive", "brain.head.profile", Color(hex: 0x9B72CF)),
        ("BDNF", "brain", Color(hex: 0x9B72CF)),
        ("Memory", "brain", Color(hex: 0x9B72CF)),
        ("Focus", "eye.fill", Color(hex: 0x9B72CF)),
        ("Anxiety", "wind", Color(hex: 0x9B72CF)),
        ("Stress", "wind", Color(hex: 0x9B72CF)),
    ]

    static func style(for benefit: String, fallbackColor: Color) -> Style {
        for mapping in mappings {
            if benefit.localizedCaseInsensitiveContains(mapping.keyword) {
                return Style(icon: mapping.icon, color: mapping.color)
            }
        }
        return Style(icon: "checkmark.seal.fill", color: fallbackColor)
    }
}
