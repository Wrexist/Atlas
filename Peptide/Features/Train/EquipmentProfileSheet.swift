import SwiftUI

/// Tick the kit a training place has: free weights, stations, each
/// machine, and the small stuff. The session builder only picks exercises
/// the ticked kit allows; bodyweight work is always on the menu.
struct EquipmentProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = EquipmentProfileStore.shared
    /// The place picked on the builder. The sheet edits that place's kit
    /// only, so its title can't disagree with where the session is built.
    let location: TrainingLocation

    private var profile: EquipmentProfile { store.profile(for: location) }

    private static let freeWeights: [EquipmentKind] = [.barbell, .dumbbell, .kettlebell, .ezBar, .trapBar]
    private static let stations: [EquipmentKind] = [.cable, .smith]
    private static let small: [EquipmentKind] = [.band, .medicineBall, .swissBall]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    Text("Atlas only plans exercises you can do with what's ticked here. Bodyweight work is always included.")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    section("FREE WEIGHTS", items: Self.freeWeights.map(Item.kind))
                    section("STATIONS", items: Self.stations.map(Item.kind) + EquipmentAccessory.allCases.map(Item.accessory))
                    section("MACHINES", items: GymMachine.allCases.map(Item.machine))
                    section("SMALL KIT", items: Self.small.map(Item.kind))
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.lg)
                .readableContentWidth()
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle(Text("Equipment · \(location.displayName)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Items

    private enum Item: Hashable {
        case kind(EquipmentKind)
        case accessory(EquipmentAccessory)
        case machine(GymMachine)

        var title: String {
            switch self {
            case .kind(let kind): kind.displayName
            case .accessory(let accessory): accessory.displayName
            case .machine(let machine): machine.displayName
            }
        }

        var glyph: AppGlyph {
            switch self {
            case .kind(let kind): kind.glyph
            case .accessory(let accessory): accessory.glyph
            case .machine: EquipmentKind.machine.glyph
            }
        }
    }

    private func isOn(_ item: Item) -> Bool {
        switch item {
        case .kind(let kind): profile.kinds.contains(kind)
        case .accessory(let accessory): profile.accessories.contains(accessory)
        case .machine(let machine): profile.machines.contains(machine)
        }
    }

    /// One write for any number of items, so "Select all" saves once.
    private func set(_ items: [Item], on: Bool) {
        var updated = profile
        for item in items {
            switch item {
            case .kind(let kind): updated.kinds.toggle(kind, on: on)
            case .accessory(let accessory): updated.accessories.toggle(accessory, on: on)
            case .machine(let machine): updated.machines.toggle(machine, on: on)
            }
        }
        store.set(updated, for: location)
    }

    // MARK: - Layout

    private func section(_ title: LocalizedStringKey, items: [Item]) -> some View {
        let allOn = items.allSatisfy(isOn)
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(AppFont.eyebrow)
                    .tracking(1.2)
                    .foregroundStyle(AppColor.textTertiary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(allOn ? LocalizedStringKey("Clear all") : LocalizedStringKey("Select all")) {
                    Haptics.selection()
                    AppAnimation.with(AppAnimation.springSnappy) {
                        set(items, on: !allOn)
                    }
                }
                .font(AppFont.footnote.weight(.semibold))
                .foregroundStyle(AppColor.accentPrimary)
                .minimumHitArea()
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)],
                      spacing: Spacing.sm) {
                ForEach(items, id: \.self) { item in
                    EquipmentTile(title: item.title, glyph: item.glyph, isOn: isOn(item)) {
                        Haptics.selection()
                        AppAnimation.with(AppAnimation.springSnappy) { set([item], on: !isOn(item)) }
                    }
                }
            }
        }
    }
}

/// One piece of kit: glyph and name, with a check that fills when ticked.
private struct EquipmentTile: View {
    let title: String
    let glyph: AppGlyph
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                GlyphImage(glyph: glyph, size: 18)
                    .foregroundStyle(isOn ? AppColor.accentPrimary : AppColor.textSecondary)
                    .frame(width: 28, height: 28)
                Text(title)
                    .font(AppFont.footnote.weight(.semibold))
                    .foregroundStyle(isOn ? AppColor.textPrimary : AppColor.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(AppFont.scaled(16))
                    .foregroundStyle(isOn ? AppColor.accentPrimary : AppColor.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 56)
            // The check and the glyph carry "on"; a tinted, outlined tile
            // as well turns a fully stocked gym into a wall of accent.
            .glassControl(
                .rect(cornerRadius: Spacing.smallCornerRadius),
                border: AppColor.glassBorder,
                interactive: false
            )
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("Equipment") {
    EquipmentProfileSheet(location: .gym)
}

private extension Set {
    mutating func toggle(_ member: Element, on: Bool) {
        if on { insert(member) } else { remove(member) }
    }
}
