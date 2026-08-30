import SwiftUI

/// One-tap starter routines for the routines empty state. Presentational
/// — the parent supplies `onPick`, which creates the routine through
/// `RoutineStore`. Mirrors `StarterHabitSuggestions`: the empty state
/// says what a routine is for, and this makes having one free.
struct StarterRoutineSuggestions: View {
    var templates: [RoutineTemplate] = RoutineTemplate.starters
    let onPick: (RoutineTemplate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("QUICK START")
                .font(AppFont.scaled(11, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(AppColor.textTertiary)

            VStack(spacing: Spacing.sm) {
                ForEach(templates) { template in
                    row(template)
                }
            }
        }
    }

    private func row(_ template: RoutineTemplate) -> some View {
        Button {
            Haptics.success()
            onPick(template)
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: template.symbolName)
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(template.name)
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("\(template.summary) · \(template.slots.count) exercises")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "plus.circle.fill")
                    .font(AppFont.scaled(20))
                    .foregroundStyle(AppColor.accentPrimary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .insetRowBackground()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Create \(template.name) routine")
        .accessibilityHint(template.summary)
    }
}

#Preview("Starter routines") {
    ScrollView {
        StarterRoutineSuggestions { _ in }
            .padding(Spacing.screenPadding)
    }
    .background(AppColor.background.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
