import SwiftUI

struct NotificationIssueBanner: View {
    let report: ScheduleReport
    let droppedProtocolNames: [String]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "bell.badge.slash.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColor.warning)
                    Text(headline)
                        .font(AppFont.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                }

                Text(detail)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline). \(detail)")
    }

    private var headline: String {
        if !report.droppedProtocolIDs.isEmpty {
            let count = report.requested - report.scheduled
            return "\(count) reminder\(count == 1 ? "" : "s") couldn't be scheduled"
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
            parts.append("Reminders for \(list) exceed iOS's \(NotificationService.pendingRequestLimit)-pending limit. Consider pausing some protocols or reducing dose times.")
        }
        if !report.invalidTimes.isEmpty {
            let list = report.invalidTimes.prefix(3).joined(separator: ", ")
            parts.append("Invalid time format: \(list).")
        }
        if !report.invalidWeekdays.isEmpty {
            parts.append("Some schedules use weekdays outside Monday–Sunday.")
        }
        return parts.joined(separator: " ")
    }
}
