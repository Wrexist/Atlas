import SwiftUI

enum BenefitStyleMap {
    struct Style {
        let icon: String
        let color: Color
    }

    private static let mappings: [(keyword: String, icon: String, color: Color)] = [
        ("Tissue Repair", "wrench.and.screwdriver.fill", Color(hex: 0x5B8FB9)),
        ("Repair", "wrench.and.screwdriver.fill", Color(hex: 0x5B8FB9)),
        ("Healing", "cross.circle.fill", Color(hex: 0x5B8FB9)),
        ("Gut", "leaf.fill", Color(hex: 0x4A7C59)),
        ("Joint", "figure.walk", Color(hex: 0x5B8FB9)),
        ("Tendon", "bandage.fill", Color(hex: 0x5B8FB9)),
        ("Flexibility", "figure.flexibility", Color(hex: 0x5B8FB9)),
        ("Hair", "comb.fill", Color(hex: 0x5B8FB9)),
        ("Skin", "hand.raised.fingers.spread.fill", Color(hex: 0xD4A844)),
        ("Muscle", "figure.strengthtraining.traditional", Color(hex: 0x4A7C59)),
        ("Growth", "arrow.up.right", Color(hex: 0x4A7C59)),
        ("GH Release", "arrow.up.circle.fill", Color(hex: 0x4A7C59)),
        ("Protein Synthesis", "atom", Color(hex: 0x4A7C59)),
        ("Cell Proliferation", "circle.grid.3x3.fill", Color(hex: 0x4A7C59)),
        ("Anti-Inflammatory", "leaf.fill", Color(hex: 0x4A7C59)),
        ("Fat Loss", "flame.fill", Color(hex: 0xE88D4F)),
        ("Fat Metabolism", "flame.fill", Color(hex: 0xE88D4F)),
        ("Metabolism", "bolt.fill", Color(hex: 0xE88D4F)),
        ("Lipolysis", "flame.fill", Color(hex: 0xE88D4F)),
        ("Weight", "scalemass.fill", Color(hex: 0xE88D4F)),
        ("Immune", "shield.checkered", Color(hex: 0xCF7272)),
        ("Antimicrobial", "shield.lefthalf.filled", Color(hex: 0xCF7272)),
        ("DNA Repair", "staroflife.fill", Color(hex: 0xCF7272)),
        ("Cardiac", "heart.fill", Color(hex: 0xCF7272)),
        ("Heart", "heart.fill", Color(hex: 0xCF7272)),
        ("Sleep", "moon.fill", Color(hex: 0xD4A844)),
        ("Deep Sleep", "moon.zzz.fill", Color(hex: 0xD4A844)),
        ("Collagen", "sparkle", Color(hex: 0xD4A844)),
        ("Anti-Aging", "hourglass", Color(hex: 0xD4A844)),
        ("Longevity", "infinity", Color(hex: 0xD4A844)),
        ("Telomere", "infinity", Color(hex: 0xD4A844)),
        ("Mood", "sun.max.fill", Color(hex: 0xD4A844)),
        ("Stress", "wind", Color(hex: 0x9B72CF)),
        ("Anxiety", "wind", Color(hex: 0x9B72CF)),
        ("Focus", "eye.fill", Color(hex: 0x9B72CF)),
        ("Memory", "brain", Color(hex: 0x9B72CF)),
        ("Cognitive", "brain.head.profile.fill", Color(hex: 0x9B72CF)),
        ("Neuroprotection", "brain.head.profile.fill", Color(hex: 0x9B72CF)),
        ("Neuroplasticity", "brain.head.profile.fill", Color(hex: 0x9B72CF)),
        ("BDNF", "brain.fill", Color(hex: 0x9B72CF)),
        ("Recovery", "arrow.counterclockwise", Color(hex: 0x5B8FB9)),
        ("Wound", "cross.circle.fill", Color(hex: 0x5B8FB9)),
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
