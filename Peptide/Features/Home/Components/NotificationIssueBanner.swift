import SwiftUI

struct NotificationIssueBanner: View {
    let report: ScheduleReport
    let droppedProtocolNames: [String]
    /// Opens the protocol list, where dose times can be trimmed.
    let onReview: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "bell.badge.slash.fill")
                                .font(AppFont.scaled(16, weight: .semibold))
                                .foregroundStyle(AppColor.warning)
                                .accessibilityHidden(true)
                            Text(headline)
                                .font(AppFont.subheadline.weight(.semibold))
                                .foregroundStyle(AppColor.textPrimary)
                        }

                        Text(detail)
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(AppFont.scaled(11, weight: .bold))
                            .foregroundStyle(AppColor.textTertiary)
                    }
                    .buttonStyle(ScalePressStyle())
                    .minimumHitArea()
                    .accessibilityLabel("Dismiss")
                }

                GlassButton(title: "Review reminders", icon: "bell.badge", style: .secondary, action: onReview)
            }
        }
    }

    private var headline: LocalizedStringKey {
        if !report.droppedProtocolIDs.isEmpty {
            let count = max(0, report.requested - report.scheduled)
            return "\(count) reminders couldn't be scheduled"
        }
        if !report.invalidTimes.isEmpty {
            return "Some reminder times couldn't be parsed"
        }
        return "Some reminders couldn't be scheduled"
    }

    private var detail: String {
        var parts: [String] = []
        if !droppedProtocolNames.isEmpty {
            let list = droppedProtocolNames.joined(separator: ", ")
            parts.append(String(localized: "iOS allows \(NotificationService.pendingRequestLimit) scheduled reminders. Reminders for \(list) won't fire — pause a protocol or trim dose times."))
        }
        if !report.invalidTimes.isEmpty {
            let list = report.invalidTimes.prefix(3).joined(separator: ", ")
            parts.append(String(localized: "Invalid time format: \(list)."))
        }
        if !report.invalidWeekdays.isEmpty {
            parts.append(String(localized: "Some schedules use weekdays outside Monday–Sunday."))
        }
        return parts.joined(separator: " ")
    }
}
