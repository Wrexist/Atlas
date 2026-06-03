import SwiftUI

/// Per-meal log shown under the macro rings on the Lifestyle tab.
/// Renders every `MealEntry` logged today, ordered newest-first,
/// grouped by category. Tap a row to edit category + delete; swipe
/// from the trailing edge for a one-tap delete shortcut.
///
/// Fills the visibility gap the auto-close success screens leave —
/// once those dismiss, users had no way to see (or fix) what got
/// logged. This card is the canonical "what did I eat today" surface.
struct TodaysMealsCard: View {
    let entries: [MealEntry]
    let onEdit: (MealEntry) -> Void
    let onDelete: (UUID) -> Void

    @State private var pendingDelete: MealEntry?

    var body: some View {
        GlassCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                header
                if entries.isEmpty {
                    emptyState
                } else {
                    rows
                }
            }
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { entry in
            Button("Delete \(entry.name)", role: .destructive) {
                onDelete(entry.id)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { entry in
            Text("Subtracts \(entry.calories) kcal from today's totals.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Today's meals")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.accentLight.opacity(0.85))
                Text(entries.isEmpty ? "Nothing logged yet" : "\(entries.count) \(entries.count == 1 ? "entry" : "entries")")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
    }

    private var emptyState: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(AppColor.textSecondary)
            Text("Log a meal to see it here. Tap any entry afterwards to edit its category or remove it.")
                .font(.system(size: 12))
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.sm)
    }

    private var rows: some View {
        VStack(spacing: Spacing.xs) {
            ForEach(entries) { entry in
                MealEntryRow(entry: entry) {
                    onEdit(entry)
                } onDelete: {
                    pendingDelete = entry
                }
            }
        }
    }
}

/// Single-row read-out for a `MealEntry`. Compact enough for the
/// stack on the Lifestyle tab without becoming a separate detail
/// screen. Swipe-from-trailing surfaces a destructive delete shortcut
/// (matches the standard iOS list behavior the user already knows
/// from Mail/Reminders/etc.).
struct MealEntryRow: View {
    let entry: MealEntry
    let onTap: () -> Void
    let onDelete: () -> Void

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.sm) {
                categoryBadge
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(entry.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Image(systemName: entry.source.icon)
                            .font(.system(size: 9))
                            .foregroundStyle(AppColor.textSecondary)
                        Text(Self.timeFormatter.string(from: entry.date))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                    Text("\(entry.calories) kcal")
                        .font(.system(size: 13, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                    Text("\(entry.proteinG)P · \(entry.carbsG)C · \(entry.fatG)F")
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .padding(.vertical, Spacing.xs)
            .padding(.horizontal, Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.35))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            // `.swipeActions` is list-only; a context menu works in
            // any container and matches the long-press pattern users
            // already know from elsewhere in the app (My Foods rows
            // in the food library use the same affordance).
            Button {
                onTap()
            } label: {
                Label("Edit category", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(for: entry))
        .accessibilityHint("Opens the entry to edit its category or delete it. Long-press for quick actions.")
    }

    private var categoryBadge: some View {
        ZStack {
            Circle()
                .fill(entry.category.tint.opacity(0.20))
                .frame(width: 30, height: 30)
            Image(systemName: entry.category.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(entry.category.tint)
        }
    }

    private static func accessibilityLabel(for entry: MealEntry) -> String {
        let time = timeFormatter.string(from: entry.date)
        return String(
            localized: "\(entry.name), \(entry.category.displayName) at \(time), \(entry.calories) kilocalories",
            comment: "VoiceOver readout for one meal entry in Today's meals list."
        )
    }
}
