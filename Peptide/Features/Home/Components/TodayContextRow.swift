import SwiftUI

/// Horizontal row of context pills sitting under WelcomeHeader.
/// Mirrors Bevel's "Active / Until changed" + "9°C / Stenungsund"
/// twin-pill pattern: glanceable context that doesn't need its own
/// section.
///
/// Left: cycle status — current protocol + day in cycle. Tappable;
/// jumps to Protocols tab so the user can see the full schedule.
/// Right: date display, styled as a pill for visual parity. Tap
/// is a no-op for now — historical-day scrubbing is a follow-up
/// commit because the Today screen has to support viewing past
/// state, not just today's.
struct TodayContextRow: View {
    let activeProtocol: PeptideProtocol?
    let date: Date
    var onTapCycle: (() -> Void)?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if let proto = activeProtocol {
                cyclePill(for: proto)
            }
            datePill
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Cycle pill

    private func cyclePill(for proto: PeptideProtocol) -> some View {
        Button {
            onTapCycle?()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "circle.dashed.rectangle")
                    .font(AppFont.scaled(11, weight: .bold))
                    .foregroundStyle(AppColor.accentLight)
                VStack(alignment: .leading, spacing: 1) {
                    Text(proto.name)
                        .font(AppFont.scaled(11, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    Text(cycleSubtitle(for: proto))
                        .font(AppFont.scaled(10, weight: .medium))
                        .foregroundStyle(AppColor.textSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(9, weight: .heavy))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background {
                Capsule().fill(AppColor.surfaceSecondary.opacity(0.7))
                    .overlay {
                        Capsule().strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cycleAccessibility(for: proto))
    }

    private func cycleSubtitle(for proto: PeptideProtocol) -> String {
        let totalDays = proto.cycleLengthWeeks * 7
        let elapsed = Calendar.current.dateComponents([.day], from: proto.startDate, to: Date()).day ?? 0
        let day = max(1, min(elapsed + 1, totalDays))
        return "Day \(day) of \(totalDays)"
    }

    private func cycleAccessibility(for proto: PeptideProtocol) -> String {
        "\(proto.name), \(cycleSubtitle(for: proto)). Tap to view full schedule."
    }

    // MARK: - Date pill

    private var datePill: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "calendar")
                .font(AppFont.scaled(11, weight: .bold))
                .foregroundStyle(AppColor.accentLight)
            Text(Self.formatter.string(from: date))
                .font(AppFont.scaled(12, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 8)
        .background {
            Capsule().fill(AppColor.surfaceSecondary.opacity(0.7))
                .overlay {
                    Capsule().strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
        .accessibilityLabel("Today, \(Self.accessibleFormatter.string(from: date))")
    }

    // Declared static so each render doesn't pay the (small)
    // allocation cost.
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f
    }()

    private static let accessibleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        return f
    }()
}

#Preview {
    // Preview shows the no-protocol case only — building a sample
    // PeptideProtocol in a preview is brittle (init signature
    // changes ripple through previews) and a snapshot env wires the
    // full row when running the app.
    ZStack {
        AppColor.background.ignoresSafeArea()
        TodayContextRow(activeProtocol: nil, date: Date())
            .padding(Spacing.lg)
    }
    .preferredColorScheme(.dark)
}
