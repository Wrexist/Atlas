import SwiftUI

/// One plate from the table, opened by tapping it: its name, what kind of
/// thing it is, a star rating, a heart, and a note on how it was.
/// Changes are handed back when the sheet closes.
struct TableDishSheet: View {
    let dish: TableDish
    let sticker: UIImage?
    let onSave: (TableDish) -> Void
    let onRemove: () -> Void

    @State private var draft: TableDish
    @State private var confirmRemove = false
    @Environment(\.dismiss) private var dismiss

    init(dish: TableDish, sticker: UIImage?, onSave: @escaping (TableDish) -> Void, onRemove: @escaping () -> Void) {
        self.dish = dish
        self.sticker = sticker
        self.onSave = onSave
        self.onRemove = onRemove
        _draft = State(initialValue: dish)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        HStack(spacing: Spacing.xs) {
                            TextField("Name it", text: $draft.name)
                                .font(AppFont.title2)
                                .foregroundStyle(AppColor.textPrimary)
                                .submitLabel(.done)
                                .accessibilityLabel("Dish name")
                            Image(systemName: "pencil")
                                .font(AppFont.scaled(13, weight: .semibold))
                                .foregroundStyle(AppColor.textTertiary)
                                .accessibilityHidden(true)
                        }
                        DishKindPicker(selection: $draft.kind)
                    }
                    if let sticker {
                        Image(uiImage: sticker)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                            .accessibilityHidden(true)
                    }
                }

                HStack(spacing: Spacing.xs) {
                    ForEach(1...5, id: \.self) { star in
                        Button {
                            draft.rating = draft.rating == star ? 0 : star
                            Haptics.selection()
                        } label: {
                            Image(systemName: star <= draft.rating ? "star.fill" : "star")
                                .font(AppFont.scaled(20, weight: .semibold))
                                .foregroundStyle(star <= draft.rating ? AppColor.accentPrimary : AppColor.textTertiary)
                                .contentTransition(.symbolEffect(.replace))
                                .scaleEffect(star == draft.rating ? 1.15 : 1)
                                .frame(width: Spacing.minimumHitTarget, height: Spacing.minimumHitTarget)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("\(star) stars"))
                        .accessibilityAddTraits(star == draft.rating ? .isSelected : [])
                    }
                    .appAnimation(AppAnimation.springBouncy, value: draft.rating)
                    Spacer(minLength: 0)
                    Button {
                        draft.isFavorite.toggle()
                        Haptics.impact(.light)
                    } label: {
                        Image(systemName: draft.isFavorite ? "heart.fill" : "heart")
                            .font(AppFont.scaled(20, weight: .semibold))
                            .foregroundStyle(draft.isFavorite ? AppColor.destructive : AppColor.textSecondary)
                            .frame(width: Spacing.minimumHitTarget, height: Spacing.minimumHitTarget)
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: draft.isFavorite)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Favorite")
                    .accessibilityAddTraits(draft.isFavorite ? .isSelected : [])
                }

                HStack(spacing: Spacing.lg) {
                    Label("\(dish.calories) kcal", systemImage: "flame")
                    Label("\(dish.proteinG) g protein", systemImage: "bolt")
                }
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textSecondary)
                .accessibilityElement(children: .combine)

                TextField("How was it? Type or talk…", text: $draft.note, axis: .vertical)
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2...6)
                    .padding(Spacing.md)
                    .glassControl(.rect(cornerRadius: Spacing.controlCornerRadius), interactive: false)
                    .accessibilityLabel("Note on this dish")

                GlassButton(title: "Remove from table", icon: "trash", style: .destructive, isFullWidth: true) {
                    confirmRemove = true
                }
            }
            .padding(Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColor.background)
        .onDisappear {
            var final = draft
            final.name = final.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if final.name.isEmpty { final.name = dish.name }
            if final != dish { onSave(final) }
        }
        .confirmationDialog("Remove this dish?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                onRemove()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It also comes off your meal log and calorie totals.")
        }
    }
}
