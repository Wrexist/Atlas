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
                    Stepper(value: $targetValue, in: Self.targetRange) {
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
                    Haptics.selection()
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
                        .scaleEffect(iconSymbol == symbol ? 1.08 : 1)
                        .minimumHitArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(HabitIconCatalog.accessibilityName(for: symbol))
                .accessibilityAddTraits(iconSymbol == symbol ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.vertical, Spacing.xs)
        .appAnimation(AppAnimation.springSnappy, value: iconSymbol)
    }

    private var colorGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 36, maximum: 44), spacing: Spacing.sm)],
                  spacing: Spacing.sm) {
            ForEach(HabitTintCatalog.all, id: \.self) { hex in
                Button {
                    Haptics.selection()
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
                    .scaleEffect(tintHex == hex ? 1.08 : 1)
                    .minimumHitArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.colorName(for: hex))
                .accessibilityAddTraits(tintHex == hex ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.vertical, Spacing.xs)
        .appAnimation(AppAnimation.springSnappy, value: tintHex)
    }

    /// Spoken name for a swatch, so VoiceOver can tell them apart.
    private static func colorName(for hex: UInt32) -> String {
        switch hex {
        case 0xCF7272: String(localized: "Red")
        case 0xE89BC4: String(localized: "Pink")
        case 0xC59FFF: String(localized: "Violet")
        case 0x9B72CF: String(localized: "Purple")
        case 0x6B8AFF: String(localized: "Blue")
        case 0x4CB8C4: String(localized: "Cyan")
        case 0x5BC489: String(localized: "Green")
        case 0xD4A844: String(localized: "Amber")
        case 0xFFB347: String(localized: "Orange")
        case 0xCFA68B: String(localized: "Brown")
        case 0x8E9499: String(localized: "Graphite")
        default:       String(localized: "Color")
        }
    }

    /// Each tap on a countable habit adds one, so a target has to be
    /// reachable by tapping.
    private static let targetRange = 1...50

    private var targetHint: LocalizedStringKey {
        switch category {
        case .health:        return "e.g. 8 (glasses of water)"
        case .fitness:       return "e.g. 3 (sets), 5 (stretch breaks)"
        case .learning:      return "e.g. 20 (pages), 1 (lesson)"
        case .mindfulness:   return "e.g. 10 (minutes meditating)"
        case .productivity:  return "e.g. 3 (deep-work blocks)"
        case .custom:        return "Set whatever number reads naturally."
        }
    }
}
