import SwiftUI

/// The most recent table on the day being viewed: its name, when, how
/// many dishes and calories, and the cut-outs piled together. Tapping it
/// opens the table.
struct LatestTableCard: View {
    let moment: TableMoment
    /// Dishes still in the diary, in table order.
    let dishes: [TableDish]
    let onOpen: () -> Void

    private var store: TableMomentStore { TableMomentStore.shared }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "sparkles")
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(AppColor.accentLight)
                    Text("Latest table")
                        .font(AppFont.eyebrow)
                        .foregroundStyle(AppColor.textSecondary)
                        .textCase(.uppercase)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(PlateTableView.title(for: moment))
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(summary)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                pile
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .background {
                        RoundedRectangle(cornerRadius: Spacing.controlCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassControl(.rect(cornerRadius: Spacing.cardCornerRadius))
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(PlateTableView.title(for: moment)), \(summary)"))
        .accessibilityHint("Opens the table.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("latest-table-card")
    }

    private var summary: String {
        let time = moment.date.formatted(date: .omitted, time: .shortened)
        let count = dishes.count == 1 ? String(localized: "1 dish") : String(localized: "\(dishes.count) dishes")
        return "\(time) · \(count) · \(dishes.reduce(0) { $0 + $1.calories }) kcal"
    }

    /// The cut-outs overlapping in a loose row, each a little turned, the
    /// way plates sit on a real table.
    private var pile: some View {
        HStack(spacing: -Spacing.xl) {
            ForEach(Array(dishes.prefix(5).enumerated()), id: \.element.id) { index, dish in
                Group {
                    if let sticker = store.sticker(for: dish) {
                        Image(uiImage: sticker)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Circle().fill(AppColor.surfaceSecondary)
                    }
                }
                .frame(width: 88, height: 88)
                .rotationEffect(.degrees(index.isMultiple(of: 2) ? -6 : 7))
                .offset(y: index.isMultiple(of: 2) ? -10 : 12)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                .staggeredAppear(index: index)
                .zIndex(Double(index))
            }
            if dishes.count > 5 {
                Text("+\(dishes.count - 5)")
                    .font(AppFont.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.leading, Spacing.xxl)
            }
        }
    }
}
