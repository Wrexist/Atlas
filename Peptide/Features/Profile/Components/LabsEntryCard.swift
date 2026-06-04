import SwiftUI

/// One-line tile in the Profile "tools" cluster. Drills into the
/// full Labs surface. Sits next to the reconstitution calculator
/// — the two share the design intent of "instrument the user's
/// workflow with utility tools, not just review surfaces".
struct LabsEntryCard: View {
    let labCount: Int
    let panelCount: Int
    let onTap: () -> Void

    var body: some View {
        GlassEntryRow(
            icon: "testtube.2",
            title: "Lab work",
            subtitle: Text(subtitleCopy),
            action: onTap
        )
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the lab-work view to log or review biomarker values over time.")
    }

    private var subtitleCopy: LocalizedStringResource {
        if labCount == 0 {
            return LocalizedStringResource("Track testosterone, IGF-1, lipids…")
        }
        return LocalizedStringResource(
            "\(labCount) entries across \(panelCount) panels",
            comment: "Subtitle on the labs entry tile when the user has at least one entry."
        )
    }

    private var accessibilityLabel: String {
        if labCount == 0 {
            return String(localized: "Lab work — no entries yet")
        }
        return String(
            localized: "Lab work — \(labCount) entries across \(panelCount) panels",
            comment: "VoiceOver readout for the labs tile."
        )
    }
}
