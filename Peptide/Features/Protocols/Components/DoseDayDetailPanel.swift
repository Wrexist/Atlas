import SwiftUI

/// Per-day dose detail panel surfaced under the calendar grid. Shows
/// every logged or scheduled mark for the currently-selected day.
///
/// Logged marks are interactive: a tap opens the dose-edit sheet for
/// that entry and a long-press surfaces an Edit / Delete context menu.
/// Scheduled marks are static — they're synthesized from the protocol
/// schedule, not real entries, so there's nothing to mutate.
///
/// The panel itself is purely a view; the caller (`TrackCalendarSection`)
/// owns the `editingEntry` state and the DataStore handles persistence,
/// keeping this file dependency-free.
struct DoseDayDetailPanel: View {
    let day: Date
    let marks: [CalendarDoseMark]
    /// Fires when the user taps a logged mark (or picks "Edit" from the
    /// context menu). `nil` when the caller hasn't wired up editing yet,
    /// in which case logged cards render non-interactively.
    var onEditEntry: ((UUID) -> Void)? = nil
    /// Fires when the user picks "Delete" from a logged mark's context
    /// menu. Caller is expected to call `DataStore.unlogDose(entryId:)`
    /// so the actual* capture fields are cleared rather than just
    /// flipping `completed`.
    var onDeleteEntry: ((UUID) -> Void)? = nil

    @State private var pendingDeletion: PendingDeletion?

    private struct PendingDeletion: Identifiable {
        let entryID: UUID
        let peptideName: String
        var id: UUID { entryID }
    }

    private var sortedMarks: [CalendarDoseMark] {
        // Logged first, then scheduled — within each group, alphabetical
        // by peptide so the order is stable across re-renders.
        marks.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind == .logged
            }
            return lhs.peptideName < rhs.peptideName
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header

            if marks.isEmpty {
                emptyState
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(sortedMarks) { mark in
                        doseCard(for: mark)
                    }
                }
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: confirmationBinding,
            presenting: pendingDeletion
        ) { item in
            Button("Remove log", role: .destructive) {
                onDeleteEntry?(item.entryID)
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: { _ in
            Text("The dose returns to its scheduled state. You can re-log it later.")
        }
    }

    private var confirmationTitle: String {
        guard let pending = pendingDeletion else { return "Remove this log?" }
        return "Remove the \(pending.peptideName) log?"
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { newValue in
                if !newValue { pendingDeletion = nil }
            }
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Spacing.xs) {
            Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Spacer(minLength: 0)
            if !marks.isEmpty {
                Text(summaryCounts)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    private var summaryCounts: String {
        let logged = marks.filter { $0.kind == .logged }.count
        let scheduled = marks.filter { $0.kind == .scheduled }.count
        switch (logged, scheduled) {
        case (let l, 0): return "\(l) logged"
        case (0, let s): return "\(s) scheduled"
        default:         return "\(logged) logged · \(scheduled) scheduled"
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        Text("No logged or scheduled doses for this day")
            .font(AppFont.subheadline)
            .foregroundStyle(AppColor.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.lg)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.5))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
            }
    }

    // MARK: - Dose card

    @ViewBuilder
    private func doseCard(for mark: CalendarDoseMark) -> some View {
        // Scheduled marks are synthesized from the protocol schedule and
        // have no entryID, so there's nothing to edit or delete — render
        // as a static row. Logged marks wrap in a Button so tapping opens
        // the edit sheet and a context menu surfaces Edit / Delete.
        if mark.kind == .logged, let entryID = mark.entryID, onEditEntry != nil {
            Button {
                onEditEntry?(entryID)
            } label: {
                cardContent(for: mark)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    onEditEntry?(entryID)
                } label: {
                    Label("Edit dose", systemImage: "pencil")
                }
                if onDeleteEntry != nil {
                    Button(role: .destructive) {
                        pendingDeletion = PendingDeletion(
                            entryID: entryID,
                            peptideName: mark.peptideName
                        )
                    } label: {
                        Label("Remove log", systemImage: "trash")
                    }
                }
            }
            .accessibilityHint("Double-tap to edit, long-press for more options")
        } else {
            cardContent(for: mark)
        }
    }

    private func cardContent(for mark: CalendarDoseMark) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            // Logged marks render the vial at the level it sat at when the
            // dose was pulled (.kind == .logged drops slightly below full
            // so the meniscus is visible); scheduled marks render full so
            // the user reads "this is what's queued, not what was taken".
            CompoundVial(
                compoundName: mark.peptideName,
                liquidLevel: mark.kind == .scheduled ? 1.0 : 0.65,
                labelText: nil,
                size: .sm
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(mark.peptideName)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    if mark.kind == .scheduled {
                        scheduledBadge
                    }
                }

                Text(mark.dose)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)

                HStack(spacing: Spacing.sm) {
                    if let time = mark.time {
                        Label(time, systemImage: "clock")
                            .labelStyle(.titleAndIcon)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textTertiary)
                    }
                    if let site = mark.injectionSite {
                        Label(site, systemImage: "mappin")
                            .labelStyle(.titleAndIcon)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }
            }

            Spacer(minLength: 0)

            if mark.kind == .logged, onEditEntry != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColor.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(Spacing.md)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
    }

    private var scheduledBadge: some View {
        Text("Scheduled")
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(AppColor.accentLight)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 2)
            .background {
                Capsule().fill(AppColor.accentPrimary.opacity(0.18))
            }
            .overlay {
                Capsule().strokeBorder(AppColor.accentPrimary.opacity(0.35), lineWidth: 0.5)
            }
    }
}
