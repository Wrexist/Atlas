import SwiftUI

/// Profile-screen card showing the user's protocol "stacks". Each row
/// is tappable and deep-links into the Protocols tab via
/// `AppState.pendingProtocolDeepLink`. The "Manage Stacks" footer
/// button and the empty-state CTA also route to that tab.
///
/// Split out of `ProfileCustomizationSheet` — the stacks rendering,
/// ordering, accessibility-label assembly, and the progress bar are
/// ~210 lines of cohesive code with no shared state with the parent's
/// avatar / identity / goals / preferences sections. Lives on its own
/// so each card is independently auditable.
struct ProfileStacksCard: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let stacks = dataStore.protocols.sorted(by: ordering)
        let activeCount = stacks.filter { $0.status == .active }.count

        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Your Stacks", systemImage: "square.stack.3d.up.fill")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    if !stacks.isEmpty {
                        Text("\(activeCount) active · \(stacks.count) total")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }

                if stacks.isEmpty {
                    emptyStacksView
                } else {
                    VStack(spacing: Spacing.xs) {
                        ForEach(stacks) { stack in
                            stackRow(stack)
                            if stack.id != stacks.last?.id {
                                Divider().foregroundStyle(AppColor.glassBorder)
                            }
                        }
                    }

                    Button {
                        if dataStore.profile.hapticFeedbackEnabled {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        appState.pendingProtocolList = true
                        appState.selectedTab = .library
                        dismiss()
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Text("Manage Stacks")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.accentPrimary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, Spacing.xs)
                    }
                    .buttonStyle(ScalePressStyle())
                }
            }
        }
    }

    private var emptyStacksView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 32))
                .foregroundStyle(AppColor.textTertiary)

            Text("No stacks yet")
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textSecondary)

            Text("Create your first protocol from the Protocols tab to start tracking doses, streaks, and compliance.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                appState.pendingProtocolList = true
                appState.selectedTab = .library
                dismiss()
            } label: {
                Label("Create Stack", systemImage: "plus")
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.accentLight)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background {
                        Capsule().fill(AppColor.accentPrimary.opacity(0.25))
                    }
            }
            .buttonStyle(ScalePressStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
    }

    private func ordering(_ a: PeptideProtocol, _ b: PeptideProtocol) -> Bool {
        if a.status != b.status {
            return statusRank(a.status) < statusRank(b.status)
        }
        return a.startDate > b.startDate
    }

    private func statusRank(_ status: ProtocolStatus) -> Int {
        switch status {
        case .active: 0
        case .paused: 1
        case .completed: 2
        }
    }

    private func stackRow(_ stack: PeptideProtocol) -> some View {
        Button {
            if dataStore.profile.hapticFeedbackEnabled {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            appState.pendingProtocolDeepLink = stack.id
            appState.pendingProtocolList = true
            appState.selectedTab = .library
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: stack.status.iconName)
                        .font(.system(size: 14))
                        .foregroundStyle(color(for: stack.status))
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(stack.name)
                            .font(AppFont.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)

                        Text(subtitle(for: stack))
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: Spacing.sm)

                    Text(stack.status.displayName)
                        .font(AppFont.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(color(for: stack.status))
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 4)
                        .background {
                            Capsule().fill(color(for: stack.status).opacity(0.15))
                        }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                }

                if stack.status == .active {
                    cycleProgressBar(for: stack)
                        .padding(.leading, 34)
                }
            }
            .padding(.vertical, Spacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: stack))
        .accessibilityHint("Opens this protocol's detail view.")
    }

    private func accessibilityLabel(for stack: PeptideProtocol) -> String {
        var parts: [String] = ["\(stack.name), \(stack.status.displayName)"]
        let abbreviations = stack.peptides.map(\.abbreviation).joined(separator: ", ")
        if !abbreviations.isEmpty {
            parts.append(abbreviations)
        }
        if stack.status == .active {
            parts.append("Week \(stack.weekNumber) of \(stack.cycleLengthWeeks)")
            parts.append("\(stack.daysRemaining) days remaining")
        }
        return parts.joined(separator: ". ")
    }

    private func cycleProgressBar(for stack: PeptideProtocol) -> some View {
        let progress = stack.cycleProgress
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColor.surfaceElevated)
                    Capsule()
                        .fill(color(for: stack.status))
                        .frame(width: max(4, geo.size.width * progress))
                }
            }
            .frame(height: 4)

            HStack {
                Text("Week \(stack.weekNumber) of \(stack.cycleLengthWeeks)")
                Spacer()
                Text("\(stack.daysRemaining) days left")
            }
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textTertiary)
            .monospacedDigit()
        }
    }

    private func subtitle(for stack: PeptideProtocol) -> String {
        let abbreviations = stack.peptides.prefix(3).map(\.abbreviation).joined(separator: " · ")
        let extras = stack.peptides.count > 3 ? " +\(stack.peptides.count - 3)" : ""
        let body = abbreviations.isEmpty ? "Empty stack" : abbreviations + extras
        return "\(body) — \(stack.schedule.summary)"
    }

    private func color(for status: ProtocolStatus) -> Color {
        switch status {
        case .active: AppColor.accentPrimary
        case .paused: AppColor.warning
        case .completed: AppColor.textSecondary
        }
    }
}
