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
/// `persistProfile()` on sheet dismissal so a session of
/// reordering lands as one save, not one per drag.
struct EditBiomarkersSheet: View {
    @Binding var config: BiologyConfig
    let isPro: Bool
    var onDismiss: () -> Void
    /// User's preferred unit so the per-row unit caption matches the rest
    /// of the Biology tab (lb / in / °F for imperial users).
    var unit: MeasurementUnit = .metric

    @Environment(\.dismiss) private var dismiss
    @State private var editMode: EditMode = .active

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
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(AppColor.accentLight)
                } footer: {
                    Text("Drag to reorder.")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColor.textSecondary)
                }

                if !config.availableBiomarkers.isEmpty {
                    Section {
                        ForEach(config.availableBiomarkers, id: \.self) { biomarker in
                            row(biomarker, action: .show)
                        }
                    } header: {
                        Text("Available")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(AppColor.accentLight)
                    } footer: {
                        Text("Add biomarkers you want to track.")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }

                if !config.hiddenBiomarkers.isEmpty {
                    Section {
                        ForEach(config.hiddenBiomarkers, id: \.self) { biomarker in
                            row(biomarker, action: .show)
                        }
                    } header: {
                        Text("Hidden")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .glassFormStyle()
            .environment(\.editMode, $editMode)
            .navigationTitle("Edit Biomarkers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDismiss()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private enum RowAction {
        case show, hide
    }

    private func row(_ biomarker: Biomarker, action: RowAction) -> some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(AppColor.surfaceElevated)
                Image(systemName: biomarker.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(biomarker.displayName)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textPrimary)
                    if biomarker.requiresPro {
                        proBadge
                    }
                }
                if let unitString = biomarker.displayUnit(for: unit) {
                    Text(unitString)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }

            Spacer(minLength: 0)

            // Toggle replaces the inline image because the user
            // expects a tap target on the right edge of each row.
            // Edit-mode drag-handle still appears on the leading
            // side of the Showing section automatically.
            Toggle(
                "",
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
            .disabled(biomarker.requiresPro && !isPro)
        }
        .padding(.vertical, 4)
        .opacity(biomarker.requiresPro && !isPro ? 0.55 : 1.0)
    }

    private var proBadge: some View {
        Text("PRO")
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .tracking(0.5)
            .foregroundStyle(AppColor.accentPrimary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background {
                Capsule().fill(AppColor.accentPrimary.opacity(0.15))
            }
    }

    private var emptyVisibleHint: some View {
        Text("You've hidden every biomarker. Tap any in the sections below to bring them back.")
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textSecondary)
            .padding(.vertical, 4)
    }

    private func toggle(_ biomarker: Biomarker) {
        // Defense in depth — the row's `Toggle` is `.disabled(...)` for
        // Pro-only biomarkers when the user isn't on Pro, but
        // VoiceOver's `accessibilityActivate`, keyboard control, or any
        // future programmatic caller can still reach this method.
        // Re-check the entitlement at the mutation site.
        guard !biomarker.requiresPro || isPro else { return }
        if config.visibleBiomarkers.contains(biomarker) {
            config.hide(biomarker)
        } else {
            config.show(biomarker)
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
                isPro: false,
                onDismiss: {}
            )
        }
    }
    return PreviewHost()
}
