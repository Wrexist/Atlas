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
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
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

    private func loggedDishes(of moment: TableMoment) -> [TableDish] {
        moment.logged(in: dataStore.mealEntries(for: moment.date))
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
        .onChange(of: canPlay) { _, allowed in if !allowed { isPlaying = false } }
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
            TableSurface()
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
            ForEach(Array(zip(dishes, cells).enumerated()), id: \.element.0.id) { index, pair in
                let (dish, cell) = pair
                Button { openDish = dish } label: {
                    VStack(spacing: Spacing.xs) {
                        plateImage(dish)
                            .frame(width: cell.width, height: cell.height)
                            .rotationEffect(.degrees(Self.restingTilt(index)))
                        if showsLabels {
                            Text(plateLabel(dish))
                                .font(AppFont.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(AppColor.textPrimary)
                                .lineLimit(1)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xxs)
                                .glassControl(.capsule, interactive: false)
                                .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .top)))
                        }
                    }
                }
                .buttonStyle(ScalePressStyle(pressedScale: 0.95))
                .staggeredAppear(index: index)
                .position(x: cell.midX, y: cell.midY + topInset)
                .accessibilityLabel(spokenPlateLabel(dish))
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
                .appShadow(AppShadow.glassSubtle)
        } else {
            Circle()
                .fill(AppColor.background)
                .overlay {
                    Image(systemName: dish.kind == .drink ? "cup.and.saucer.fill" : "fork.knife")
                        .font(AppFont.scaled(24, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                }
                .appShadow(AppShadow.glassSubtle)
        }
    }

    /// Each plate sits a little turned, the way nobody sets a table on a
    /// grid. Fixed per position so the table looks the same every visit.
    private static func restingTilt(_ index: Int) -> Double {
        [-5, 4, -3, 6, -6, 3, -4, 5][index % 8]
    }

    private func plateLabel(_ dish: TableDish) -> String {
        dish.rating > 0 ? "\(dish.name) ★\(dish.rating)" : dish.name
    }

    /// VoiceOver reads the ★ glyph as "black star".
    private func spokenPlateLabel(_ dish: TableDish) -> Text {
        dish.rating > 0 ? Text("\(dish.name), rated \(dish.rating) of 5 stars") : Text(dish.name)
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
                toggle("Labels", icon: showsLabels ? "tag.fill" : "tag", isOn: showsLabels) {
                    showsLabels.toggle()
                    scene.setLabelsVisible(showsLabels)
                }
                if canPlay {
                    toggle("Play", icon: "dot.circle.and.hand.point.up.left.fill", isOn: isPlaying) {
                        togglePlay()
                    }
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
                            .minimumHitArea()
                    }
                    GlassIconButton(icon: "arrow.counterclockwise", accessibilityLabel: "Toss the plates", size: 36) {
                        scene.toss()
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
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
                .contentTransition(.symbolEffect(.replace))
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

    /// Tilt physics is motion Reduce Motion asks to avoid, and plates in
    /// play can't be opened one by one with VoiceOver, so both keep the
    /// table at rest.
    private var canPlay: Bool { !reduceMotion && !voiceOverEnabled }

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

            .sectionAppear(index: 0)

            stats(moment, dishes: dishes)
                .sectionAppear(index: 1)

            TextField("How was it? Type or talk…", text: $note, axis: .vertical)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(2...6)
                .focused($noteFocused)
                .padding(Spacing.md)
                .glassControl(.rect(cornerRadius: Spacing.controlCornerRadius), interactive: false)
                .accessibilityLabel("Note on this meal")
                .sectionAppear(index: 2)
        }
    }

    /// Time, dishes, calories and protein as four small tiles; the numbers
    /// roll when a dish is edited or taken off.
    private func stats(_ moment: TableMoment, dishes: [TableDish]) -> some View {
        let calories = dishes.reduce(0) { $0 + $1.calories }
        let protein = dishes.reduce(0) { $0 + $1.proteinG }
        return HStack(spacing: Spacing.sm) {
            TableStatTile(icon: "clock", value: moment.date.formatted(date: .omitted, time: .shortened), unit: String(localized: "time"))
            TableStatTile(icon: "fork.knife", value: "\(dishes.count)", unit: dishes.count == 1 ? String(localized: "dish") : String(localized: "dishes"))
            TableStatTile(icon: "flame.fill", value: "\(calories)", unit: String(localized: "kcal"))
            TableStatTile(icon: "bolt.fill", value: "\(protein) g", unit: String(localized: "protein"))
        }
        .appAnimation(AppAnimation.settle, value: [dishes.count, calories, protein])
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

/// One figure under the table: a tinted glyph, the value, and its unit.
private struct TableStatTile: View {
    let icon: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Image(systemName: icon)
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .accessibilityHidden(true)
            Text(value)
                .font(AppFont.scaled(16, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(unit)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .glassControl(.rect(cornerRadius: Spacing.controlCornerRadius), interactive: false)
        .accessibilityElement(children: .combine)
    }
}

/// The table the plates rest on: a soft dotted cloth that fades into the
/// page below, so the plates sit on something without a hard edge.
private struct TableSurface: View {
    var body: some View {
        AppColor.surfaceSecondary
            .overlay {
                Canvas { context, size in
                    let step: CGFloat = 18
                    var dots = Path()
                    for x in stride(from: step / 2, to: size.width, by: step) {
                        for y in stride(from: step / 2, to: size.height, by: step) {
                            dots.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                        }
                    }
                    context.fill(dots, with: .color(AppColor.textTertiary.opacity(0.18)))
                }
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [AppColor.background.opacity(0), AppColor.background], startPoint: .top, endPoint: .bottom)
                    .frame(height: 64)
            }
            .accessibilityHidden(true)
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
                        .appShadow(AppShadow.glassSubtle)
                        .position(x: cell.midX, y: cell.midY)
                }
            }
            .frame(width: 360, height: 360)
            VStack(spacing: Spacing.xxs) {
                Text(title)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("\(calories) kcal · Atlas")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(Spacing.xxl)
        .background(AppColor.background)
    }
}
