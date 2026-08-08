import SwiftUI

/// Everything `HabitEditSheet` moved off its first screen: category,
/// icon, colour, an optional numeric target, and the exact reminder time.
/// These are the decisions a habit can be *tuned* with, as opposed to the
/// ones it can't exist without, so they get a push instead of a slot in
/// the main column.
///
/// Every value is a binding back into the sheet — this screen owns no
/// state of its own, so backing out of it keeps the edits and the sheet
/// stays the single thing that commits.
struct HabitCustomizeView: View {
    @Binding var category: HabitCategory
    @Binding var iconSymbol: String
    @Binding var tintHex: UInt32
    @Binding var enableTarget: Bool
    @Binding var targetValue: Int
    @Binding var enableReminder: Bool
    @Binding var reminderTime: Date

    private var tint: Color { Color(hex: UInt(tintHex)) }

    var body: some View {
        Form {
            Section {
                Picker("Category", selection: $category) {
                    ForEach(HabitCategory.allCases) { c in
                        Label(c.displayName, systemImage: c.icon).tag(c)
                    }
                }
            }

            Section("Icon") {
                iconGrid
            }

            Section("Color") {
                colorGrid
            }

            Section("Target") {
                Toggle("Track a count", isOn: $enableTarget)
                if enableTarget {
                    Stepper(value: $targetValue, in: 1...100000, step: targetStep) {
                        HStack {
                            Text("Target")
                            Spacer()
                            Text("\(targetValue)")
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                    Text(targetHint)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }
            }

            Section {
                Toggle("Daily reminder", isOn: $enableReminder)
                if enableReminder {
                    DatePicker(
                        "Time",
                        selection: $reminderTime,
                        displayedComponents: .hourAndMinute
                    )
                }
            } header: {
                Text("Reminder")
            } footer: {
                Text("Setting an exact time here also moves the morning / afternoon / evening choice on the previous screen.")
            }
        }
        .glassFormStyle()
        .navigationTitle("Customize")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var iconGrid: some View {
        // `.adaptive` so the grid reflows to fit the available width —
        // a hard-coded column count breaks on the narrowest iPhone,
        // where 36pt × 6 doesn't fit (audit 4.13).
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 40, maximum: 48), spacing: Spacing.sm)],
                  spacing: Spacing.sm) {
            ForEach(HabitIconCatalog.all, id: \.self) { symbol in
                Button {
                    Haptics.impact(.soft)
                    iconSymbol = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(iconSymbol == symbol ? tint : AppColor.textSecondary)
                        .frame(width: 36, height: 36)
                        .background {
                            Circle().fill(iconSymbol == symbol
                                          ? tint.opacity(0.18)
                                          : AppColor.surfaceSecondary.opacity(0.6))
                        }
                        .overlay {
                            Circle().stroke(iconSymbol == symbol ? tint : Color.clear,
                                            lineWidth: 1)
                        }
                        .minimumHitArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbol)
                .accessibilityAddTraits(iconSymbol == symbol ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private var colorGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 36, maximum: 44), spacing: Spacing.sm)],
                  spacing: Spacing.sm) {
            ForEach(HabitTintCatalog.all, id: \.self) { hex in
                Button {
                    Haptics.impact(.soft)
                    tintHex = hex
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: UInt(hex)))
                            .frame(width: 32, height: 32)
                        if tintHex == hex {
                            Image(systemName: "checkmark")
                                .font(AppFont.scaled(13, weight: .bold))
                                .foregroundStyle(AppColor.onAccent)
                        }
                    }
                    .overlay {
                        Circle().stroke(
                            tintHex == hex ? AppColor.textPrimary.opacity(0.9) : Color.clear,
                            lineWidth: 1.5
                        )
                    }
                    .minimumHitArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color")
                .accessibilityAddTraits(tintHex == hex ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    /// Bigger step for big-number targets so the stepper isn't useless at
    /// 10,000 steps.
    private var targetStep: Int {
        if targetValue >= 10000 { return 500 }
        if targetValue >= 1000  { return 100 }
        if targetValue >= 100   { return 10 }
        return 1
    }

    private var targetHint: LocalizedStringKey {
        switch category {
        case .health:        return "e.g. 8 (glasses of water), 10000 (steps)"
        case .fitness:       return "e.g. 30 (minutes), 100 (push-ups)"
        case .learning:      return "e.g. 20 (pages), 1 (lesson)"
        case .mindfulness:   return "e.g. 10 (minutes meditating)"
        case .productivity:  return "e.g. 3 (deep-work blocks)"
        case .custom:        return "Set whatever number reads naturally."
        }
    }
}
