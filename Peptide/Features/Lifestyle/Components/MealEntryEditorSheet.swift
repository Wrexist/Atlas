import SwiftUI

/// Edit-or-delete sheet for an existing `MealEntry`. Reached from
/// `TodaysMealsCard` by tapping a row. Keeps the surface tiny — the
/// only things a user typically wants to fix on a past log are the
/// meal category (auto-detect occasionally lands on the wrong bucket
/// near a boundary) and "I shouldn't have logged this at all". For
/// macro corrections the user logs again via the food library and
/// deletes the duplicate; building a full macro re-editor inline
/// would be scope creep this sheet doesn't need.
struct MealEntryEditorSheet: View {
    let initial: MealEntry
    let onSave: (MealEntry) -> Void
    let onDelete: (UUID) -> Void
    let onCancel: () -> Void

    @State private var category: MealCategory
    @State private var showDeleteConfirm: Bool = false

    init(
        initial: MealEntry,
        onSave: @escaping (MealEntry) -> Void,
        onDelete: @escaping (UUID) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initial = initial
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _category = State(initialValue: initial.category)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    summaryCard
                    MealCategoryPicker(selection: $category)
                    macrosCard
                    deleteButton
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxxxl)
            }
            .scrollIndicators(.hidden)
            .background(AppColor.background)
            .navigationTitle("Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: commit)
                        .disabled(category == initial.category)
                }
            }
            .confirmationDialog(
                "Delete this entry?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    onDelete(initial.id)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Subtracts \(initial.calories) kcal from today's totals. This can't be undone.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var summaryCard: some View {
        GlassCard(padding: Spacing.md) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(MealEntryRow.tint(for: initial.category).opacity(0.20))
                        .frame(width: 44, height: 44)
                    Image(systemName: initial.category.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(MealEntryRow.tint(for: initial.category))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(initial.name)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Image(systemName: initial.source.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(AppColor.textSecondary)
                        Text(Self.timeFormatter.string(from: initial.date))
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                        // `sourceID` may point to a custom food the
                        // user has since deleted, or an OFF barcode
                        // that's been evicted from the cache. The
                        // entry remains valid — we just rely on
                        // `entry.name` for display rather than trying
                        // to dereference the source. No "Re-log this"
                        // shortcut here for the same reason.
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var macrosCard: some View {
        GlassCard(tinted: true, padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Logged values")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Divider().background(AppColor.glassBorder)
                macroRow(label: "Calories", value: "\(initial.calories) kcal")
                macroRow(label: "Protein",  value: "\(initial.proteinG) g")
                macroRow(label: "Carbs",    value: "\(initial.carbsG) g")
                macroRow(label: "Fat",      value: "\(initial.fatG) g")
                Text("To change macros, delete this entry and re-log via the food library.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.xs)
            }
        }
    }

    private func macroRow(label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            Text(value)
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "trash")
                Text("Delete this entry")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
        }
        .buttonStyle(.bordered)
        .tint(AppColor.destructive)
    }

    private func commit() {
        var updated = initial
        updated.category = category
        onSave(updated)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}
