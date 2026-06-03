import SwiftUI

/// The "is my stack healthy?" cluster on the Protocols tab. Owns
/// the four cards that read the stack-recommendation engine's
/// output — completeness, interaction warnings, cycle transitions,
/// and the HealthKit sync banner — plus the two follow-up sheets a
/// warning tap triggers (detail → adjustment).
///
/// Phase 34 moved this content out of HomeView so the Today tab is
/// the daily action surface and the Protocols tab is the
/// configuration surface. Everything here is read-only on the stack
/// state; mutating taps route through `dataStore.updateProtocol`,
/// `addPeptide`, `addProtocol` exactly as they did on Home.
struct ProtocolsStackHealthSection: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState

    /// `selectedAlert` drives the warning-detail sheet. Set when the
    /// user taps a warning row; cleared on dismiss.
    @State private var selectedAlert: StackRecommendationEngine.Warning?
    /// `adjustingAlert` drives the follow-up adjustment sheet that
    /// the detail's primary CTA hands off to. Two-sheet chaining
    /// (rather than a push) so the user can compare side-by-side
    /// without losing the warning context.
    @State private var adjustingAlert: StackRecommendationEngine.Warning?
    /// Paywall trigger for the rare adjustment branch that needs a
    /// new protocol on a Pro-only account.
    @State private var showPaywall = false

    var body: some View {
        let warnings = dataStore.stackWarnings
        let completeness = dataStore.stackCompleteness
        let transitions = dataStore.cycleTransitions

        // Only render the section when it has at least one card to
        // show. Without this guard a clean stack (no warnings, no
        // transitions, no completeness gap) would leave the header
        // dangling above nothing — which would look like a missing
        // section, not a healthy one.
        if completeness != nil
            || !warnings.isEmpty
            || !transitions.isEmpty
            || dataStore.profile.healthConnected
        {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HomeSectionHeader(eyebrow: "Stack health", title: "How it's holding up")

                if let completeness {
                    StackCompletenessCard(completeness: completeness)
                }

                if !warnings.isEmpty {
                    StackWarningCard(
                        warnings: warnings,
                        onSelect: { selectedAlert = $0 }
                    )
                }

                if !transitions.isEmpty {
                    CycleTransitionCard(transitions: transitions)
                }

                if dataStore.profile.healthConnected {
                    HealthSummaryCard()
                }
            }
            .sheet(item: $selectedAlert) { warning in
                StackAlertDetailSheet(
                    warning: warning,
                    peptideDatabase: dataStore.peptideDatabase,
                    onPrimaryAction: {
                        if canAdjustStack(for: warning) {
                            // Defer until the detail sheet finishes
                            // dismissing — SwiftUI can't chain two
                            // sheets in the same runloop tick.
                            Task { @MainActor in
                                try? await Task.sleep(for: AppAnimation.sheetDismissDelay)
                                adjustingAlert = warning
                            }
                        } else {
                            // No adjustable protocol — the warning
                            // is informational only. Already on the
                            // Protocols tab so we just dismiss and
                            // let the user navigate.
                            selectedAlert = nil
                        }
                    }
                )
            }
            .sheet(item: $adjustingAlert) { warning in
                let candidates = StackAdjustmentEngine.candidateProtocols(
                    affectedAbbreviations: warning.peptides,
                    in: dataStore.activeProtocols
                )
                StackAdjustmentSheet(
                    warning: warning,
                    candidateProtocols: candidates,
                    allActiveProtocols: dataStore.activeProtocols,
                    peptideDatabase: dataStore.peptideDatabase,
                    onApply: applyStackAdjustment
                )
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .liquidGlassPresentation()
            }
        }
    }

    private func canAdjustStack(for warning: StackRecommendationEngine.Warning) -> Bool {
        let candidates = StackAdjustmentEngine.candidateProtocols(
            affectedAbbreviations: warning.peptides,
            in: dataStore.activeProtocols
        )
        return !candidates.isEmpty
    }

    private func applyStackAdjustment(_ result: StackAdjustmentResult) {
        guard let source = dataStore.activeProtocols.first(where: { $0.id == result.sourceProtocolId })
        else { return }

        dataStore.updateProtocol(
            id: source.id,
            name: source.name,
            peptides: result.updatedPeptides,
            schedule: source.schedule,
            peptideSchedules: source.peptideSchedules,
            cycleLengthWeeks: source.cycleLengthWeeks,
            washoutWeeks: source.washoutWeeks,
            notes: source.notes
        )

        var deferredPaywall = false
        for move in result.moves {
            switch move.destination {
            case .discard:
                continue
            case .moveTo(let protocolId, _, _):
                dataStore.addPeptide(move.peptide, toProtocolId: protocolId)
            case .createStack:
                if StoreService.shared.requiresPro(activeProtocolCount: dataStore.activeProtocols.count) {
                    deferredPaywall = true
                    continue
                }
                let newStack = PeptideProtocol(
                    id: UUID(),
                    name: "\(move.peptide.abbreviation) Solo",
                    peptides: [move.peptide],
                    schedule: source.schedule,
                    cycleLengthWeeks: source.cycleLengthWeeks,
                    startDate: Date(),
                    status: .active,
                    notes: "Spun off from \(source.name) to reduce compounding side effects."
                )
                dataStore.addProtocol(newStack)
            }
        }
        if deferredPaywall { showPaywall = true }
    }
}
