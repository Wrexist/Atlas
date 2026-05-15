import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Lock-screen + Dynamic Island Live Activity for an in-progress
/// dose window. Premium redesign (Phase 31) — every surface speaks
/// the same status state machine so a glance reads the same on the
/// lock screen, in the compact pill, or in the expanded island.
///
/// State priorities:
///   • upcoming — soft accent ring growing toward the dose time
///   • dueNow   — full-bleed accent, "Take now" CTA, Log button
///                lights up
///   • late     — amber accent, "X min late" pill
///   • completed— green pill with a checkmark, auto-dismissing
///
/// The activity is started by `DoseLiveActivityService` from the
/// iOS app whenever a dose enters its "active window" (default:
/// 30 min before doseTime → 90 min after). The interactive "Log"
/// button (iOS 17+) fires `LogDoseLiveActivityIntent`, which both
/// updates the activity state immediately and queues a marker the
/// main app drains on next foreground.
@available(iOS 16.1, *)
struct DoseWindowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DoseWindowAttributes.self) { context in
            DoseWindowLockView(
                attributes: context.attributes,
                state: context.state
            )
            // Tapping anywhere outside the Log button deep-links
            // into the matching dose row in the app.
            .widgetURL(deepLink(for: context.attributes.entryId))
        } dynamicIsland: { context in
            buildDynamicIsland(context: context)
        }
    }

    @available(iOS 16.1, *)
    private func buildDynamicIsland(
        context: ActivityViewContext<DoseWindowAttributes>
    ) -> DynamicIsland {
        let tint = Color(hex: context.attributes.tintHex)
        return DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                IslandLeadingBadge(
                    tint: tint,
                    state: context.state
                )
            }
            DynamicIslandExpandedRegion(.trailing) {
                IslandTrailingTimer(
                    state: context.state,
                    accent: statusAccent(for: context.state, tint: tint)
                )
            }
            DynamicIslandExpandedRegion(.center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.attributes.peptideAbbreviation)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(context.attributes.doseDisplay)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            DynamicIslandExpandedRegion(.bottom) {
                IslandBottomBar(
                    entryId: context.attributes.entryId,
                    state: context.state,
                    tint: tint
                )
            }
        } compactLeading: {
            CompactLeading(
                tint: statusAccent(for: context.state, tint: tint),
                state: context.state
            )
        } compactTrailing: {
            CompactTrailing(
                state: context.state,
                accent: statusAccent(for: context.state, tint: tint)
            )
        } minimal: {
            MinimalGlyph(
                tint: statusAccent(for: context.state, tint: tint),
                state: context.state
            )
        }
        .widgetURL(deepLink(for: context.attributes.entryId))
        .keylineTint(statusAccent(for: context.state, tint: tint))
    }

    /// Custom deep link scheme for tapping into the matching dose
    /// row. `PeptideApp.onOpenURL` parses the host + entry UUID
    /// and surfaces the logging sheet.
    private func deepLink(for entryId: UUID) -> URL? {
        URL(string: "peptidex://dose/\(entryId.uuidString)")
    }
}

// MARK: - Status colour helpers

@available(iOS 16.1, *)
private func statusAccent(
    for state: DoseWindowAttributes.ContentState,
    tint: Color
) -> Color {
    switch state.status() {
    case .upcoming:  return tint
    case .dueNow:    return tint
    case .late:      return Color(red: 1.00, green: 0.70, blue: 0.20) // amber
    case .completed: return Color(red: 0.36, green: 0.78, blue: 0.55) // green
    }
}

@available(iOS 16.1, *)
private func statusGlyph(
    for state: DoseWindowAttributes.ContentState
) -> String {
    switch state.status() {
    case .completed: return "checkmark.circle.fill"
    case .late:      return "exclamationmark.circle.fill"
    default:         return "syringe.fill"
    }
}

@available(iOS 16.1, *)
private func statusShortLabel(
    for state: DoseWindowAttributes.ContentState
) -> String {
    switch state.status() {
    case .upcoming(let minutes):
        if minutes >= 60 {
            let hours = minutes / 60
            return "in \(hours)h"
        }
        return "in \(minutes)m"
    case .dueNow:
        return "now"
    case .late(let minutes):
        return "\(minutes)m late"
    case .completed:
        return "Logged"
    }
}

// MARK: - Lock-screen view

@available(iOS 16.1, *)
private struct DoseWindowLockView: View {
    let attributes: DoseWindowAttributes
    let state: DoseWindowAttributes.ContentState

    private var tint: Color { Color(hex: attributes.tintHex) }
    private var accent: Color { statusAccent(for: state, tint: tint) }
    private var status: DoseWindowAttributes.ContentState.Status {
        state.status()
    }

    var body: some View {
        ZStack {
            // Full-bleed gradient backdrop — adapts to status so
            // the late / completed flips read at a glance even
            // before the user focuses on the copy.
            LinearGradient(
                colors: [
                    accent.opacity(0.30),
                    accent.opacity(0.05),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 12) {
                topRow
                bottomRow
            }
            .padding(14)
        }
        .activityBackgroundTint(Color.black.opacity(0.05))
        .activitySystemActionForegroundColor(.white)
    }

    private var topRow: some View {
        HStack(alignment: .center, spacing: 14) {
            LockProgressRing(
                progress: state.windowProgress(),
                accent: accent,
                glyph: statusGlyph(for: state)
            )
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(attributes.peptideName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(attributes.doseDisplay)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(attributes.peptideAbbreviation)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            StatusPill(state: state, accent: accent)
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 10) {
            timerColumn
            Spacer(minLength: 0)
            actionButton
        }
    }

    @ViewBuilder
    private var timerColumn: some View {
        switch status {
        case .completed:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Logged")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.primary)
                    if let loggedAt = state.loggedAt {
                        Text(loggedAt, style: .time)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .late:
            HStack(spacing: 6) {
                Text(state.doseTime, style: .relative)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                Text("late")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        case .dueNow:
            VStack(alignment: .leading, spacing: 0) {
                Text("Take now")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                Text(state.doseTime, style: .time)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        case .upcoming:
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(state.doseTime, style: .timer)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text("to dose")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if state.completed {
            EmptyView()
        } else {
            Button(intent: LogDoseLiveActivityIntent(entryId: attributes.entryId)) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .heavy))
                    Text("Log")
                        .font(.system(size: 14, weight: .heavy))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.75)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: accent.opacity(0.45), radius: 6, y: 2)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Lock-screen ring

@available(iOS 16.1, *)
private struct LockProgressRing: View {
    let progress: Double
    let accent: Color
    let glyph: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.18), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    AngularGradient(
                        colors: [accent.opacity(0.65), accent, accent.opacity(0.85)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(accent.opacity(0.20))
                .padding(8)
            Image(systemName: glyph)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(accent)
                .shadow(color: accent.opacity(0.45), radius: 4, y: 1)
        }
    }
}

// MARK: - Lock-screen status pill

@available(iOS 16.1, *)
private struct StatusPill: View {
    let state: DoseWindowAttributes.ContentState
    let accent: Color

    var body: some View {
        let label = statusShortLabel(for: state)
        HStack(spacing: 5) {
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, weight: .heavy))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(accent.opacity(0.18))
                .overlay {
                    Capsule().strokeBorder(accent.opacity(0.40), lineWidth: 0.5)
                }
        }
    }
}

// MARK: - Dynamic Island — compact / minimal / expanded pieces

@available(iOS 16.1, *)
private struct CompactLeading: View {
    let tint: Color
    let state: DoseWindowAttributes.ContentState

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.30), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.001, state.windowProgress()))
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: statusGlyph(for: state))
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(tint)
        }
        .frame(width: 22, height: 22)
        .padding(.leading, 2)
    }
}

@available(iOS 16.1, *)
private struct CompactTrailing: View {
    let state: DoseWindowAttributes.ContentState
    let accent: Color

    var body: some View {
        switch state.status() {
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(accent)
                .padding(.trailing, 2)
        case .dueNow:
            Text("Now")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(accent)
                .padding(.trailing, 2)
        case .late:
            HStack(spacing: 2) {
                Text(state.doseTime, style: .relative)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
            }
            .padding(.trailing, 2)
        case .upcoming:
            Text(state.doseTime, style: .timer)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.trailing, 2)
        }
    }
}

@available(iOS 16.1, *)
private struct MinimalGlyph: View {
    let tint: Color
    let state: DoseWindowAttributes.ContentState

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.22))
            Image(systemName: statusGlyph(for: state))
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(tint)
        }
    }
}

// MARK: - Dynamic Island — expanded pieces

@available(iOS 16.1, *)
private struct IslandLeadingBadge: View {
    let tint: Color
    let state: DoseWindowAttributes.ContentState

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [tint, tint.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: tint.opacity(0.55), radius: 6, y: 2)
            Image(systemName: statusGlyph(for: state))
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: 38, height: 38)
    }
}

@available(iOS 16.1, *)
private struct IslandTrailingTimer: View {
    let state: DoseWindowAttributes.ContentState
    let accent: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            primaryText
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent)
            Text(statusShortLabel(for: state))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private var primaryText: some View {
        switch state.status() {
        case .completed:
            Text("✓")
        case .late:
            Text(state.doseTime, style: .relative)
        case .dueNow:
            Text(state.doseTime, style: .time)
        case .upcoming:
            Text(state.doseTime, style: .timer)
        }
    }
}

@available(iOS 16.1, *)
private struct IslandBottomBar: View {
    let entryId: UUID
    let state: DoseWindowAttributes.ContentState
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            // Mini progress arc + dose-time label keeps the user
            // oriented even when they expand the island late.
            ProgressLabel(state: state, tint: tint)
            Spacer(minLength: 0)
            actionButton
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var actionButton: some View {
        if state.completed {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .heavy))
                Text("Logged")
                    .font(.system(size: 13, weight: .heavy))
            }
            .foregroundStyle(Color(red: 0.36, green: 0.78, blue: 0.55))
        } else {
            Button(intent: LogDoseLiveActivityIntent(entryId: entryId)) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .heavy))
                    Text("Log dose")
                        .font(.system(size: 13, weight: .heavy))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint, tint.opacity(0.75)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .buttonStyle(.plain)
        }
    }
}

@available(iOS 16.1, *)
private struct ProgressLabel: View {
    let state: DoseWindowAttributes.ContentState
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.25), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0.001, state.windowProgress()))
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text("Window")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.55))
                    .textCase(.uppercase)
                    .tracking(0.4)
                Text(state.doseTime, style: .time)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

// MARK: - Colour helper

private extension Color {
    init(hex: UInt) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
