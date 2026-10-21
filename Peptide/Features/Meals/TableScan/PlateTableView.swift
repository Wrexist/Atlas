import SpriteKit
import SwiftUI

/// A kept table, full screen: the plates laid out on top, the meal's
/// details below. Labels names the plates; Play hands them to physics,
/// where they tumble toward wherever the phone tilts and can be flicked
/// around. Tapping a plate opens it.
struct PlateTableView: View {
    let momentID: UUID
    let onClose: () -> Void

    @Environment(DataStore.self) private var dataStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene = PlateTableScene(size: CGSize(width: 1, height: 1))
    @State private var isPlaying = false
    @State private var showsLabels = true
    @State private var mode: PlateTableScene.Mode = .tumble
    @State private var tableSize: CGSize = .zero
    @State private var openDish: TableDish?
    @State private var note = ""
    @State private var isAdding = false
    @State private var shareImage: Image?
    @FocusState private var noteFocused: Bool

    private var store: TableMomentStore { TableMomentStore.shared }

    var body: some View {
        Group {
            if let moment = store.moment(id: momentID) {
                content(moment, dishes: loggedDishes(of: moment))
            } else {
                Color.clear.onAppear(perform: onClose)
            }
        }
        .background(AppColor.background.ignoresSafeArea())
        .overlay { TableSaveToast() }
    }

    /// Dishes whose diary entry still exists. Deleting a meal from the
    /// diary takes its plate off the table too.
    private func loggedDishes(of moment: TableMoment) -> [TableDish] {
        let logged = Set(dataStore.mealEntries(for: moment.date).map(\.id))
        return moment.dishes.filter { logged.contains($0.id) }
    }

    private func content(_ moment: TableMoment, dishes: [TableDish]) -> some View {
        VStack(spacing: 0) {
            table(dishes)
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical) { height, _ in height * 0.48 }
                .overlay(alignment: .top) { controls }

            ScrollView {
                details(moment, dishes: dishes)
                    .padding(Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) { footer(moment, dishes: dishes) }
        .onAppear { note = moment.note }
        .onDisappear { saveNote() }
        .onChange(of: noteFocused) { _, focused in if !focused { saveNote() } }
        .task(id: dishes.map(\.id)) { renderShareImage(moment, dishes: dishes) }
        .onChange(of: dishes.map(\.id)) { _, _ in if isPlaying { startPhysics(dishes) } }
        .sheet(item: $openDish) { dish in
            TableDishSheet(
                dish: dish,
                sticker: store.sticker(for: dish),
                onSave: { save($0, in: moment) },
                onRemove: { remove(dish, from: moment) }
            )
            .presentationDetents([.medium, .large])
            .liquidGlassPresentation()
        }
        .sheet(isPresented: $isAdding) {
            TableScanFlow(
                addingTo: moment,
                onKeep: { draft in
                    isAdding = false
                    Task { await store.keep(draft, in: dataStore) }
                },
                onClose: { isAdding = false }
            )
            .environment(dataStore)
        }
    }

    // MARK: - Table

    private func table(_ dishes: [TableDish]) -> some View {
        ZStack {
            AppColor.surfaceSecondary
            if isPlaying {
                SpriteView(scene: scene, options: [.allowsTransparency])
                    .accessibilityLabel("Plates in play. Tilt your phone to move them.")
            } else {
                restingPlates(dishes)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { tableSize = $0 }
        .clipped()
    }

    /// The plates at rest, where Play will let go of them.
    private func restingPlates(_ dishes: [TableDish]) -> some View {
        let cells = PlateTableLayout.cells(count: dishes.count, in: tableArea)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(zip(dishes, cells)), id: \.0.id) { dish, cell in
                Button { openDish = dish } label: {
                    VStack(spacing: Spacing.xxs) {
                        plateImage(dish)
                            .frame(width: cell.width, height: cell.height)
                        if showsLabels {
                            Text(plateLabel(dish))
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textPrimary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(ScalePressStyle(pressedScale: 0.95))
                .position(x: cell.midX, y: cell.midY + topInset)
                .accessibilityLabel(Text(plateLabel(dish)))
                .accessibilityHint("Opens this dish.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .appAnimation(AppAnimation.settle, value: showsLabels)
    }

    @ViewBuilder
    private func plateImage(_ dish: TableDish) -> some View {
        if let sticker = store.sticker(for: dish) {
            Image(uiImage: sticker)
                .resizable()
                .scaledToFit()
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        } else {
            Circle()
                .fill(AppColor.background)
                .overlay {
                    Image(systemName: dish.kind == .drink ? "cup.and.saucer.fill" : "fork.knife")
                        .font(AppFont.scaled(24, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                }
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
    }

    private func plateLabel(_ dish: TableDish) -> String {
        dish.rating > 0 ? "\(dish.name) ★\(dish.rating)" : dish.name
    }

    /// Room under the floating controls, so a plate at rest never sits
    /// beneath a button.
    private var topInset: CGFloat { 96 }

    private var tableArea: CGSize {
        CGSize(width: tableSize.width, height: max(0, tableSize.height - topInset))
    }

    private var controls: some View {
        VStack(alignment: .trailing, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                GlassIconButton(icon: "chevron.left", accessibilityLabel: "Back", size: 36) { onClose() }
                Spacer(minLength: 0)
                toggle("Labels", icon: "tag", isOn: showsLabels) {
                    showsLabels.toggle()
                    scene.setLabelsVisible(showsLabels)
                }
                toggle("Play", icon: "dot.circle.and.hand.point.up.left.fill", isOn: isPlaying) {
                    togglePlay()
                }
            }
            if isPlaying {
                HStack(spacing: Spacing.sm) {
                    Menu {
                        Picker("Mode", selection: $mode) {
                            ForEach(PlateTableScene.Mode.allCases) { option in
                                Label(option.label, systemImage: option.icon).tag(option)
                            }
                        }
                    } label: {
                        Label(mode.label, systemImage: mode.icon)
                            .font(AppFont.footnote)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.textPrimary)
                            .padding(.horizontal, Spacing.md)
                            .frame(minHeight: 36)
                            .glassControl(.capsule)
                    }
                    GlassIconButton(icon: "arrow.counterclockwise", accessibilityLabel: "Toss the plates", size: 36) {
                        scene.toss()
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
        .onChange(of: mode) { _, mode in scene.setMode(mode) }
    }

    private func toggle(_ title: LocalizedStringKey, icon: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.selection()
        } label: {
            Label(title, systemImage: icon)
                .font(AppFont.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(isOn ? AppColor.onAccent : AppColor.textPrimary)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: 36)
                .background { if isOn { Capsule().fill(AppColor.accentFill) } }
                .glassControl(.capsule)
        }
        .buttonStyle(ScalePressStyle())
        .minimumHitArea()
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func togglePlay() {
        let dishes = store.moment(id: momentID).map(loggedDishes(of:)) ?? []
        if !isPlaying { startPhysics(dishes) }
        AppAnimation.with(AppAnimation.fadeIn) { isPlaying.toggle() }
    }

    private func startPhysics(_ dishes: [TableDish]) {
        let cells = PlateTableLayout.cells(count: dishes.count, in: tableArea)
        let plates = zip(dishes, cells).compactMap { dish, cell -> PlateTableScene.Plate? in
            guard let sticker = store.sticker(for: dish) ?? placeholderPlate(dish) else { return nil }
            let frame = PlateTableLayout.fit(sticker.size, in: cell).offsetBy(dx: 0, dy: topInset)
            return .init(id: dish.id, image: sticker, label: plateLabel(dish), frame: frame)
        }
        scene.size = tableSize
        scene.onTap = { id in openDish = dishes.first { $0.id == id } }
        scene.place(plates, labelColor: UIColor(AppColor.textPrimary))
        scene.setLabelsVisible(showsLabels)
        scene.setMode(mode)
    }

    /// A plain plate for a dish whose cut-out isn't on this device.
    private func placeholderPlate(_ dish: TableDish) -> UIImage? {
        let renderer = ImageRenderer(content: plateImage(dish).frame(width: 160, height: 160))
        renderer.scale = 2
        return renderer.uiImage
    }

    // MARK: - Details

    private func details(_ moment: TableMoment, dishes: [TableDish]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(Self.title(for: moment))
                    .font(AppFont.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColor.textPrimary)
                Capsule()
                    .fill(AppColor.accentPrimary)
                    .frame(width: 40, height: 3)
                    .accessibilityHidden(true)
            }

            HStack(spacing: Spacing.md) {
                Label(moment.date.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                Label(dishes.count == 1 ? String(localized: "1 dish") : String(localized: "\(dishes.count) dishes"), systemImage: "fork.knife")
                Label("\(dishes.reduce(0) { $0 + $1.calories }) kcal", systemImage: "flame")
                Label("\(dishes.reduce(0) { $0 + $1.proteinG }) g protein", systemImage: "bolt")
            }
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .combine)

            TextField("How was it? Type or talk…", text: $note, axis: .vertical)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(2...6)
                .focused($noteFocused)
                .padding(Spacing.md)
                .glassControl(.rect(cornerRadius: Spacing.controlCornerRadius), interactive: false)
                .accessibilityLabel("Note on this meal")
        }
    }

    static func title(for moment: TableMoment) -> String {
        "\(moment.category.displayName) · \(moment.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
    }

    private func footer(_ moment: TableMoment, dishes: [TableDish]) -> some View {
        HStack(spacing: Spacing.md) {
            if let shareImage {
                ShareLink(
                    item: shareImage,
                    preview: SharePreview(Self.title(for: moment), image: shareImage)
                ) {
                    Label("Share this moment", systemImage: "square.and.arrow.up")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Capsule().fill(AppColor.accentFill))
                }
                .buttonStyle(ScalePressStyle())
            }
            GlassIconButton(icon: "plus", accessibilityLabel: "Add dishes to this table", size: 52) {
                isAdding = true
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
        .background(AppColor.background)
    }

    // MARK: - Writes

    private func saveNote() {
        guard var moment = store.moment(id: momentID), moment.note != note else { return }
        moment.note = note
        store.update(moment)
    }

    /// Writes the plate back, and carries a rename into the diary so the
    /// meal log says what the table says.
    private func save(_ dish: TableDish, in moment: TableMoment) {
        guard var current = store.moment(id: moment.id),
              let index = current.dishes.firstIndex(where: { $0.id == dish.id }) else { return }
        let renamed = current.dishes[index].name != dish.name
        current.dishes[index] = dish
        store.update(current)
        if renamed, var entry = dataStore.mealEntries(for: moment.date).first(where: { $0.id == dish.id }) {
            entry.name = dish.name
            dataStore.updateMealEntry(entry)
        }
        if isPlaying { startPhysics(loggedDishes(of: current)) }
    }

    private func remove(_ dish: TableDish, from moment: TableMoment) {
        store.remove(dishID: dish.id, from: moment.id)
        dataStore.unlogMealEntry(id: dish.id)
        Haptics.impact(.medium)
    }

    private func renderShareImage(_ moment: TableMoment, dishes: [TableDish]) {
        let card = TableShareCard(
            title: Self.title(for: moment),
            stickers: dishes.compactMap { store.sticker(for: $0) },
            calories: dishes.reduce(0) { $0 + $1.calories }
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        shareImage = renderer.uiImage.map { Image(uiImage: $0) }
    }
}

/// The image "Share this moment" sends: the cut-outs on a card with the
/// meal's name. Rendered once per change of plates, never laid out on
/// screen.
struct TableShareCard: View {
    let title: String
    let stickers: [UIImage]
    let calories: Int

    var body: some View {
        VStack(spacing: Spacing.lg) {
            let cells = PlateTableLayout.cells(count: stickers.count, in: CGSize(width: 360, height: 360))
            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(stickers.indices, cells)), id: \.0) { index, cell in
                    Image(uiImage: stickers[index])
                        .resizable()
                        .scaledToFit()
                        .frame(width: cell.width, height: cell.height)
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                        .position(x: cell.midX, y: cell.midY)
                }
            }
            .frame(width: 360, height: 360)
            VStack(spacing: Spacing.xxs) {
                Text(title)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("\(calories) kcal · Atlas")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(Spacing.xxl)
        .background(AppColor.background)
    }
}
