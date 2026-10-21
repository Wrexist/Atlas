import SwiftUI

/// Drag-to-reorder + show/hide editor for the Biology tab's
/// biomarker list. Three sections — Showing (draggable),
/// Available (never-added), Hidden (deliberately off) — so the
/// user can tell the difference between "I haven't seen this
/// yet" and "I turned this off". Pro-gated biomarkers carry a
/// small PRO chip.
///
/// Writes through the binding the host wires to
/// `dataStore.profile.biologyConfig`; the host calls
/// `persistProfile()` from the sheet's `onDismiss` so a session of
/// reordering lands as one save, not one per drag.
struct EditBiomarkersSheet: View {
    @Binding var config: BiologyConfig
    let isPro: Bool
    /// User's preferred unit so the per-row unit caption matches the rest
    /// of the Biology tab (lb / in / °F for imperial users).
    var unit: MeasurementUnit = .metric

    @Environment(\.dismiss) private var dismiss
    @State private var editMode: EditMode = .active
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if config.visibleBiomarkers.isEmpty {
                        emptyVisibleHint
                    } else {
                        ForEach(config.visibleBiomarkers, id: \.self) { biomarker in
                            row(biomarker, action: .hide)
                        }
                        .onMove { from, to in
                            var next = config.visibleBiomarkers
                            next.move(fromOffsets: from, toOffset: to)
                            config.reorder(next)
                        }
                    }
                } header: {
                    Text("Showing")
                        .font(AppFont.scaled(11, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(AppColor.textSecondary)
                } footer: {
                    Text("Drag to reorder.")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(AppColor.textSecondary)
                }

                if !config.availableBiomarkers.isEmpty {
                    Section {
                        ForEach(config.availableBiomarkers, id: \.self) { biomarker in
                            row(biomarker, action: .show)
                        }
                    } header: {
                        Text("Available")
                            .font(AppFont.scaled(11, weight: .heavy, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(AppColor.textSecondary)
                    } footer: {
                        Text("Add biomarkers you want to track.")
                            .font(AppFont.scaled(11))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }

                if !restorableBiomarkers.isEmpty {
                    Section {
                        ForEach(restorableBiomarkers, id: \.self) { biomarker in
                            row(biomarker, action: .show)
                        }
                    } header: {
                        Text("Hidden")
                            .font(AppFont.scaled(11, weight: .heavy, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .glassFormStyle()
            .environment(\.editMode, $editMode)
            .navigationTitle("Edit biomarkers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: .performanceAge)
                    .liquidGlassPresentation()
            }
        }
    }

    /// Hidden biomarkers that can still show data. One without a data
    /// source stays off once hidden, matching `availableBiomarkers`.
    private var restorableBiomarkers: [Biomarker] {
        config.hiddenBiomarkers.filter(\.hasDataSource)
    }

    private enum RowAction {
        case show, hide
    }

    private func row(_ biomarker: Biomarker, action: RowAction) -> some View {
        let needsPro = biomarker.requiresPro && !isPro
        // Only turning a Pro row *on* needs Pro; one left showing after a
        // lapse can always be turned off.
        let locked = needsPro && action == .show
        return HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(AppColor.surfaceElevated)
                Image(systemName: biomarker.icon)
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(biomarker.displayName)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textPrimary)
                    if biomarker.requiresPro {
                        ProBadge()
                    }
                }
                if let unitString = biomarker.displayUnit(for: unit) {
                    Text(unitString)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                if needsPro && action == .hide {
                    Text("Paused without Pro")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }

            Spacer(minLength: 0)

            // Toggle replaces the inline image because the user
            // expects a tap target on the right edge of each row.
            // Edit-mode drag-handle still appears on the leading
            // side of the Showing section automatically. A Pro-only
            // row the user can't turn on routes to the paywall instead.
            if locked {
                Button {
                    Haptics.selection()
                    showPaywall = true
                } label: {
                    Image(systemName: "lock.fill")
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                        .minimumHitArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Unlock \(biomarker.displayName) with Pro"))
            } else {
                visibilityToggle(for: biomarker, action: action)
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func visibilityToggle(for biomarker: Biomarker, action: RowAction) -> some View {
        Toggle(
            biomarker.displayName,
            isOn: Binding(
                get: { action == .hide },
                set: { newOn in
                    guard newOn != (action == .hide) else { return }
                    toggle(biomarker)
                }
            )
        )
        .labelsHidden()
        .toggleStyle(.switch)
        .tint(AppColor.accentPrimary)
    }

    private var emptyVisibleHint: some View {
        Text("You've hidden every biomarker. Turn one on below to bring it back.")
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textSecondary)
            .padding(.vertical, Spacing.xs)
    }

    private func toggle(_ biomarker: Biomarker) {
        let isVisible = config.visibleBiomarkers.contains(biomarker)
        // Defense in depth — a locked Pro-only row shows a lock in
        // place of its `Toggle` when the user isn't on Pro, but
        // VoiceOver's `accessibilityActivate`, keyboard control, or any
        // future programmatic caller can still reach this method.
        // Re-check the entitlement at the mutation site. Hiding is
        // always allowed.
        guard isVisible || !biomarker.requiresPro || isPro else { return }
        Haptics.selection()
        AppAnimation.with(AppAnimation.springSnappy) {
            if isVisible {
                config.hide(biomarker)
            } else {
                config.show(biomarker)
            }
        }
    }
}

#Preview {
    struct PreviewHost: View {
        @State var config = BiologyConfig(
            visibleBiomarkers: [.weight, .hrvBaseline, .rhrBaseline],
            hiddenBiomarkers: [.sleepBaseline]
        )
        var body: some View {
            EditBiomarkersSheet(
                config: $config,
                isPro: false
            )
        }
    }
    return PreviewHost()
}
