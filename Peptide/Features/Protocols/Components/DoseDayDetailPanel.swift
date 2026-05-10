import SwiftUI

/// Per-day dose detail panel surfaced under the calendar grid. Shows
/// every logged or scheduled mark for the currently-selected day. Cards
/// are read-only in this iteration — swipe-to-delete and tap-to-edit
/// dose modals are tracked as separate work items.
struct DoseDayDetailPanel: View {
    let day: Date
    let marks: [CalendarDoseMark]

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

    private func doseCard(for mark: CalendarDoseMark) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            // Logged marks render the vial at the level it sat at when the
            // dose was pulled (.kind == .logged drops slightly below full
            // so the meniscus is visible); scheduled marks render full so
            // the user reads "this is what's queued, not what was taken".
            VialIllustration(
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
        }
        .padding(Spacing.md)
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
