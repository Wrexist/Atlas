import Foundation
import SwiftUI

/// Pure-function cycle-phase classifier. Given a protocol's start
/// date, on-cycle duration, and wash-out duration, computes which
/// phase the protocol is in *right now* (or on any reference date),
/// the user-facing labels, and the headline numbers (day-of-phase,
/// total-phase-length).
///
/// Powers the cycle-phase card on the protocol detail view and a
/// future Home-tab callout when the user is approaching the
/// phase boundary. The math is small enough to call on every
/// render — no caching needed at this layer.
enum CyclePhaseEngine {

    /// Where the protocol sits in its cycle right now.
    enum Phase: Equatable, Sendable {
        /// User is in the active "on" phase. `day` = 1-based day
        /// number within the on-cycle. `totalDays` = on-cycle
        /// length in days.
        case onCycle(day: Int, totalDays: Int)
        /// User is in the wash-out period between cycles. Same
        /// shape as `.onCycle` so the renderer can branch once.
        case washout(day: Int, totalDays: Int)
        /// Protocol has no wash-out configured and the on-cycle
        /// has finished — natural end. Different from
        /// `.washout(day: total, total)` because there's no
        /// scheduled return.
        case completed
        /// Protocol hasn't started yet. Used by the Home-tab
        /// "starts in N days" callout.
        case upcoming(daysUntilStart: Int)
    }

    struct Status: Equatable, Sendable {
        let phase: Phase
        /// Date the current phase ends. For `.completed` and
        /// `.upcoming`, the start of the next phase if there is one.
        let phaseEndDate: Date
        /// 0...1 progress through the current phase. Drives the
        /// progress bar in the UI.
        let phaseProgress: Double
        /// Cycle number (1-based) — the protocol's third on-phase
        /// reads as "Cycle 3 · Week 5 of 8". For protocols with
        /// `washoutWeeks == 0`, this stays at 1.
        let cycleNumber: Int
    }

    /// Compute the protocol's phase status as of `referenceDate`.
    /// Default is "now" — pass a different date for unit testing
    /// boundary conditions without mocking the clock.
    static func status(for proto: PeptideProtocol, at referenceDate: Date = Date()) -> Status {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: referenceDate)
        let start = calendar.startOfDay(for: proto.startDate)
        let onDays = proto.safeCycleLengthWeeks * 7
        let washDays = max(0, proto.washoutWeeks) * 7
        let cyclePeriod = onDays + washDays

        if now < start {
            let days = calendar.dateComponents([.day], from: now, to: start).day ?? 0
            return Status(
                phase: .upcoming(daysUntilStart: max(0, days)),
                phaseEndDate: start,
                phaseProgress: 0,
                cycleNumber: 1
            )
        }

        let elapsedDays = calendar.dateComponents([.day], from: start, to: now).day ?? 0

        // No-wash-out path: the protocol runs one cycle then ends.
        // Matches the original `endDate` behaviour for back-compat
        // with every existing user.
        if washDays == 0 {
            if elapsedDays >= onDays {
                return Status(
                    phase: .completed,
                    phaseEndDate: calendar.date(byAdding: .day, value: onDays, to: start) ?? start,
                    phaseProgress: 1.0,
                    cycleNumber: 1
                )
            }
            let endOfPhase = calendar.date(byAdding: .day, value: onDays, to: start) ?? start
            return Status(
                phase: .onCycle(day: elapsedDays + 1, totalDays: onDays),
                phaseEndDate: endOfPhase,
                phaseProgress: Double(elapsedDays) / Double(onDays),
                cycleNumber: 1
            )
        }

        // Repeating-cycle path: alternating on/off.
        let cycleNumber = elapsedDays / cyclePeriod + 1
        let dayInCycle = elapsedDays % cyclePeriod
        let cycleStart = calendar.date(byAdding: .day, value: (cycleNumber - 1) * cyclePeriod, to: start) ?? start

        if dayInCycle < onDays {
            let endOfOn = calendar.date(byAdding: .day, value: onDays, to: cycleStart) ?? start
            return Status(
                phase: .onCycle(day: dayInCycle + 1, totalDays: onDays),
                phaseEndDate: endOfOn,
                phaseProgress: Double(dayInCycle) / Double(onDays),
                cycleNumber: cycleNumber
            )
        } else {
            let dayInWash = dayInCycle - onDays
            let endOfWash = calendar.date(byAdding: .day, value: cyclePeriod, to: cycleStart) ?? start
            return Status(
                phase: .washout(day: dayInWash + 1, totalDays: washDays),
                phaseEndDate: endOfWash,
                phaseProgress: Double(dayInWash) / Double(washDays),
                cycleNumber: cycleNumber
            )
        }
    }

    // MARK: - Render helpers

    /// User-facing label for the phase. Splits into title + subtitle
    /// pairs so the card can render them in two different type
    /// styles without re-parsing.
    static func labels(for status: Status) -> (title: String, subtitle: String) {
        switch status.phase {
        case .onCycle(let day, let total):
            return (
                String(localized: "On cycle"),
                String(
                    localized: "Day \(day) of \(total)",
                    comment: "Subtitle on the cycle-phase card during the active dosing phase."
                )
            )
        case .washout(let day, let total):
            return (
                String(localized: "Wash-out"),
                String(
                    localized: "Day \(day) of \(total)",
                    comment: "Subtitle on the cycle-phase card during the off phase."
                )
            )
        case .completed:
            return (
                String(localized: "Cycle complete"),
                String(localized: "Protocol finished — start a new cycle to continue.")
            )
        case .upcoming(let days):
            let dayWord = days == 1
                ? String(localized: "1 day")
                : String(localized: "\(days) days")
            return (
                String(localized: "Upcoming"),
                String(
                    localized: "Starts in \(dayWord)",
                    comment: "Subtitle on the cycle-phase card before the protocol's start date."
                )
            )
        }
    }

    /// Accent colour for the phase. Mirrors the warm-to-cool tint
    /// language used elsewhere — "on" reads as energetic accent,
    /// "wash-out" as cooler purple, "completed" as neutral.
    static func tint(for phase: Phase) -> Color {
        switch phase {
        case .onCycle:  return AppColor.accentPrimary
        case .washout:  return Color(red: 0.55, green: 0.50, blue: 0.85)
        case .completed: return AppColor.textSecondary
        case .upcoming: return AppColor.accentLight
        }
    }

    /// SF Symbol for the phase. Picked to read at glance even when
    /// the card is rendered small (compact-tab summary card).
    static func icon(for phase: Phase) -> String {
        switch phase {
        case .onCycle:  return "syringe.fill"
        case .washout:  return "moon.stars.fill"
        case .completed: return "checkmark.seal.fill"
        case .upcoming: return "calendar"
        }
    }
}
