import ActivityKit
import AppIntents
import SwiftUI
import UIKit
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
///   • late     — amber accent, "Late" pill. An unlogged dose stays
///                here: the one stale-date redraw is spent moving into
///                Late, and the app ends the activity once the window
///                closes.
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
                    if !context.attributes.doseDisplay.isEmpty {
                        Text(context.attributes.doseDisplay)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                }
                // Redacted on a locked device, as the home and lock
                // screen widgets redact the same names and doses.
                .privacySensitive()
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
    case .late:      return WidgetPalette.over
    case .completed: return WidgetPalette.done
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
    case .upcoming:
        return String(localized: "Due \(state.doseTime.formatted(date: .omitted, time: .shortened))")
    case .dueNow:
        return String(localized: "now")
    case .late:
        return String(localized: "Late")
    case .completed:
        return String(localized: "Logged")
    }
}

// MARK: - Lock-screen view

@available(iOS 16.1, *)
private struct DoseWindowLockView: View {
    let attributes: DoseWindowAttributes
    let state: DoseWindowAttributes.ContentState
    @Environment(\.colorScheme) private var colorScheme

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
                state: state,
                accent: accent,
                glyph: statusGlyph(for: state)
            )
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(attributes.peptideName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .privacySensitive()
                HStack(spacing: 6) {
                    if !attributes.doseDisplay.isEmpty {
                        Text(attributes.doseDisplay)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.secondary)
                    }
                    Text(attributes.peptideAbbreviation)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .lineLimit(1)
                .privacySensitive()
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
                Text(timerInterval: state.countdownInterval(), countsDown: true)
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
                .foregroundStyle(labelColor(on: accent, in: colorScheme))
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
    let state: DoseWindowAttributes.ContentState
    let accent: Color
    let glyph: String

    var body: some View {
        ZStack {
            WindowRing(state: state, tint: accent, lineWidth: 5)
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

// MARK: - Window ring

/// Fills from `windowStart` to `doseTime` on its own. A Live Activity
/// only re-renders on a push, so a ring drawn from `Date()` would freeze
/// at whatever fraction it had at the last update; the system timer
/// view keeps advancing between pushes. Logged doses draw a full ring.
@available(iOS 16.1, *)
private struct WindowRing: View {
    let state: DoseWindowAttributes.ContentState
    let tint: Color
    let lineWidth: CGFloat

    var body: some View {
        if state.completed {
            Circle()
                .stroke(tint, lineWidth: lineWidth)
        } else {
            ProgressView(timerInterval: state.windowInterval, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(tint)
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
            WindowRing(state: state, tint: tint, lineWidth: 2)
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

    @ViewBuilder
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
            // A count-up timer stays "1:12:00" past the hour, where the
            // relative style grows to "1 hr, 12 min" and spills the pill.
            Text(state.doseTime, style: .timer)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: 44)
                .padding(.trailing, 2)
        case .upcoming:
            Text(timerInterval: state.countdownInterval(), countsDown: true)
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
            statusText
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
    private var statusText: some View {
        switch state.status() {
        case .completed:
            // The "Logged" caption underneath already speaks the state.
            Image(systemName: "checkmark")
                .accessibilityHidden(true)
        case .late:
            Text(state.doseTime, style: .timer)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        case .dueNow:
            Text(state.doseTime, style: .time)
        case .upcoming:
            Text(timerInterval: state.countdownInterval(), countsDown: true)
        }
    }
}

@available(iOS 16.1, *)
private struct IslandBottomBar: View {
    let entryId: UUID
    let state: DoseWindowAttributes.ContentState
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

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
            .foregroundStyle(WidgetPalette.done)
        } else {
            Button(intent: LogDoseLiveActivityIntent(entryId: entryId)) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .heavy))
                    Text("Log dose")
                        .font(.system(size: 13, weight: .heavy))
                }
                .foregroundStyle(labelColor(on: tint, in: colorScheme))
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
            WindowRing(state: state, tint: tint, lineWidth: 3)
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

// MARK: - Colour helpers

/// Black or white, whichever reads better on `fill`. Vial tints run from
/// deep to pale, and the late amber is light, so a fixed white label
/// fails contrast on some of the fills the Log button takes. The late
/// amber is a light/dark pair, so it is resolved against the scheme the
/// view draws in, not whatever trait collection is current.
private func labelColor(on fill: Color, in colorScheme: ColorScheme) -> Color {
    let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    guard UIColor(fill).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a) else { return .white }
    func linear(_ channel: CGFloat) -> Double {
        let c = Double(channel)
        return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    // Above this, black text out-contrasts white (WCAG relative luminance).
    return luminance > 0.179 ? .black : .white
}

private extension Color {
    init(hex: UInt) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
