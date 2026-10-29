import PhotosUI
import SwiftUI
import UserNotifications

/// Add or edit one thing in the fridge.
///
/// A photo is lifted off its background on-device and read by the smart
/// scan for a name and macros; a barcode fills the exact product from a
/// saved product or Open Food Facts. Either way every field stays
/// editable. The use-by date seeds itself from how long the product kept
/// last time, or a cautious default, and asks for notifications once so
/// the fridge can remind.
struct FridgeItemEditor: View {
    enum Shortcut: Hashable { case camera, barcode }

    /// The row being edited; nil adds a new one.
    var item: FridgeItem?
    /// Saved product to start from: a re-add from search, or the edited row's.
    var product: FridgeProduct?
    /// Opens the camera or the barcode scanner straight away.
    var shortcut: Shortcut?
    let onClose: () -> Void

    @Environment(\.locale) private var locale
    @State private var store = FridgeStore.shared
    @State private var storeService = StoreService.shared

    @State private var name = ""
    @State private var brand = ""
    @State private var amount = ""
    @State private var count = 1
    @State private var place: FridgePlace = .fridge
    @State private var hasDate = false
    @State private var expiresOn = Date()
    @State private var dateTouched = false
    @State private var pantryKey: String?
    @State private var keyPicked = false
    @State private var per100g: ScannedProduct.Nutriments?
    @State private var imageURL: URL?
    @State private var barcode: String?
    @State private var sticker: UIImage?
    @State private var stickerIsNew = false

    @State private var isLifting = false
    @State private var isReading = false
    @State private var status: String?
    @State private var showCamera = false
    @State private var showBarcode = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var showConsent = false
    @State private var cameraDenied = false
    @State private var confirmForget = false
    @State private var hydrated = false

    private var calendar: Calendar { .current }
    private var isEditing: Bool { item != nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var ingredients: [LibraryRecipe.Ingredient] {
        var seen: Set<String> = []
        return RecipeLibraryEngine.bundled.flatMap(\.ingredients)
            .filter { seen.insert($0.pantryKey).inserted }
            .sorted { $0.displayName(locale: locale).localizedCompare($1.displayName(locale: locale)) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                pictureSection
                productSection
                kitchenSection
                dateSection
                recipeSection
                if let item { editActions(item) }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "Edit item" : "Add to fridge")
            .navigationBarTitleDisplayMode(.inline)
            .glassFormStyle()
            .appAnimation(AppAnimation.springSnappy, value: hasDate)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add", action: save)
                        .disabled(trimmedName.isEmpty || isLifting)
                }
            }
        }
        .onAppear(perform: hydrate)
        .onChange(of: name) { _, name in matchKey(name) }
        .onChange(of: pantryKey) { _, _ in seedDate() }
        .onChange(of: place) { _, _ in seedDate() }
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            libraryItem = nil
            Task { await importPhoto(item) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(
                onPicked: { image in
                    showCamera = false
                    Task { await lift(image) }
                },
                onCancel: { showCamera = false },
                cameraDevice: .rear,
                allowsEditing: false
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showBarcode) {
            FridgeBarcodeSheet(
                onCode: { code in
                    showBarcode = false
                    Task { await lookUp(code) }
                },
                onClose: { showBarcode = false }
            )
            .presentationDetents([.large])
            .liquidGlassPresentation()
        }
        .sheet(isPresented: $showConsent, onDismiss: readAfterConsent) {
            AIConsentSheet(whatIsSent: "The cut-out photo of the product you add.")
                .liquidGlassPresentation()
        }
        .alert("Camera access is off", isPresented: $cameraDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow camera access in Settings, or pick a photo from your library.")
        }
    }

    // MARK: - Sections

    private var pictureSection: some View {
        Section {
            VStack(spacing: Spacing.md) {
                ZStack {
                    if let sticker {
                        Image(uiImage: sticker)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 150)
                            .rotationEffect(.degrees(-3))
                            .appShadow(AppShadow.glassElevated)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    } else if let product = currentProductForImage {
                        FridgeProductImage(product: product, size: 120)
                    } else {
                        Image(systemName: "refrigerator")
                            .font(AppFont.scaled(40, weight: .semibold, relativeTo: .largeTitle))
                            .foregroundStyle(AppColor.textTertiary)
                            .frame(height: 120)
                            .accessibilityHidden(true)
                    }
                    if isLifting { ProgressView().tint(AppColor.accentPrimary) }
                }
                .frame(maxWidth: .infinity, minHeight: 150)
                .appAnimation(AppAnimation.liftFly, value: sticker)

                if let status {
                    Text(status)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                HStack(spacing: Spacing.sm) {
                    pictureButton("Photo", icon: "camera.fill", action: openCamera)
                    PhotosPicker(selection: $libraryItem, matching: .images, photoLibrary: .shared()) {
                        pictureLabel("Library", icon: "photo.on.rectangle")
                    }
                    .buttonStyle(ScalePressStyle())
                    pictureButton("Barcode", icon: "barcode.viewfinder") { showBarcode = true }
                }
                .disabled(isLifting || isReading)
            }
            .padding(.vertical, Spacing.sm)
        } footer: {
            Text("A photo loses its background automatically. A barcode gives the exact product.")
        }
    }

    /// The saved picture to show before a new photo is taken.
    private var currentProductForImage: FridgeProduct? {
        guard let product, product.hasPhoto || product.imageURL != nil else { return nil }
        return product
    }

    private func pictureButton(_ title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { pictureLabel(title, icon: icon) }
            .buttonStyle(ScalePressStyle())
    }

    private func pictureLabel(_ title: LocalizedStringKey, icon: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(AppFont.scaled(16, weight: .semibold))
            Text(title)
                .font(AppFont.caption2)
        }
        .foregroundStyle(AppColor.textPrimary)
        .frame(maxWidth: .infinity, minHeight: Spacing.minimumHitTarget + Spacing.md)
        .glassControl(.rect(cornerRadius: Spacing.smallCornerRadius))
    }

    private var productSection: some View {
        Section("Product") {
            TextField("Name (e.g. Milk)", text: $name)
                .textInputAutocapitalization(.sentences)
            TextField("Brand (optional)", text: $brand)
                .textInputAutocapitalization(.words)
            TextField("Amount (e.g. 1 l, 500 g)", text: $amount)
        }
    }

    private var kitchenSection: some View {
        Section("Kept in") {
            GlassSegmentedControl(
                options: FridgePlace.allCases,
                selected: $place,
                label: { $0.label },
                icon: { $0.icon }
            )
            Stepper(value: $count, in: 1...99) {
                HStack {
                    Text("How many")
                    Spacer()
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }

    private var dateSection: some View {
        Section {
            Toggle("Use-by date", isOn: hasDateBinding)
                .tint(AppColor.accentPrimary)
            if hasDate {
                DatePicker("Use by", selection: dateBinding, displayedComponents: .date)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        quickDate("Tomorrow", days: 1)
                        quickDate("3 days", days: 3)
                        quickDate("1 week", days: 7)
                        quickDate("2 weeks", days: 14)
                        quickDate("1 month", days: 30)
                    }
                }
            }
        } footer: {
            Text("Atlas reminds you the evening before, and puts what is about to go off first.")
        }
    }

    private var hasDateBinding: Binding<Bool> {
        Binding(get: { hasDate }, set: { hasDate = $0; dateTouched = true })
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { expiresOn }, set: { expiresOn = $0; dateTouched = true })
    }

    private func quickDate(_ title: LocalizedStringKey, days: Int) -> some View {
        Button {
            expiresOn = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: .now)) ?? .now
            dateTouched = true
            Haptics.selection()
        } label: {
            Text(title)
                .font(AppFont.chipText)
                .foregroundStyle(AppColor.textPrimary)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: 32)
                .glassControl(.capsule)
        }
        .buttonStyle(ScalePressStyle())
        .minimumHitArea()
    }

    private var recipeSection: some View {
        Section {
            Picker("Counts as", selection: keyBinding) {
                Text("Nothing in recipes").tag(String?.none)
                ForEach(ingredients, id: \.pantryKey) { ingredient in
                    Text(ingredient.displayName(locale: locale)).tag(Optional(ingredient.pantryKey))
                }
            }
            .pickerStyle(.navigationLink)
        } header: {
            Text("Recipes")
        } footer: {
            Text("Recipes and the weekly shopping list count it as at home while it's in date.")
        }
    }

    private var keyBinding: Binding<String?> {
        Binding(get: { pantryKey }, set: { pantryKey = $0; keyPicked = true })
    }

    private func editActions(_ item: FridgeItem) -> some View {
        Section {
            Button {
                store.useOne(item.id)
                Haptics.success()
                onClose()
            } label: {
                Label(item.count > 1 ? "Used one" : "Used it up", systemImage: "fork.knife")
            }
            Button(role: .destructive) {
                store.remove(item.id)
                Haptics.impact(.light)
                onClose()
            } label: {
                Label("Throw out", systemImage: "trash")
            }
            Button(role: .destructive) {
                confirmForget = true
            } label: {
                Label("Forget this product", systemImage: "xmark.bin")
            }
            .confirmationDialog("Forget this product?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Forget", role: .destructive) {
                    store.forget(item.productID)
                    onClose()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It leaves the fridge and your saved products.")
            }
        }
    }

    // MARK: - Filling

    private func hydrate() {
        guard !hydrated else { return }
        hydrated = true
        if let product { fill(from: product) }
        if let item {
            count = item.count
            place = item.place
            if let date = item.expiresOn {
                hasDate = true
                expiresOn = date
            }
            dateTouched = true
            keyPicked = true
        } else {
            seedDate()
        }
        switch shortcut {
        case .camera: openCamera()
        case .barcode: showBarcode = true
        case nil: break
        }
    }

    private func fill(from product: FridgeProduct) {
        name = product.name
        brand = product.brand ?? ""
        amount = product.amount ?? ""
        place = product.place
        pantryKey = product.pantryKey
        keyPicked = product.pantryKey != nil
        per100g = product.per100g
        imageURL = product.imageURL
        barcode = product.barcode
    }

    private func matchKey(_ name: String) {
        guard !keyPicked else { return }
        pantryKey = FridgeEngine.pantryKey(for: name, ingredients: ingredients)
    }

    /// A date from the saved product's last shelf life, else the cautious
    /// default, until the user sets one.
    private func seedDate() {
        guard !dateTouched else { return }
        let days = product?.shelfDays ?? FridgeEngine.defaultShelfDays(place: place, pantryKey: pantryKey)
        guard let date = FridgeEngine.expiry(from: .now, shelfDays: days, calendar: calendar) else {
            hasDate = false
            return
        }
        hasDate = true
        expiresOn = date
    }

    private func openCamera() {
        Task {
            switch await CameraAuthorization.resolve() {
            case .granted where UIImagePickerController.SourceType.cameraIsAvailable:
                showCamera = true
            case .granted:
                status = String(localized: "No camera here. Pick a photo from your library.")
            case .denied, .restricted:
                cameraDenied = true
            }
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            status = String(localized: "Couldn't open that photo. Try another one.")
            return
        }
        await lift(image)
    }

    private func lift(_ photo: UIImage) async {
        isLifting = true
        status = String(localized: "Removing the background…")
        let lifted = await FridgeLiftEngine.liftSingle(from: photo)
        isLifting = false
        guard let lifted else {
            status = String(localized: "Couldn't read that photo. Try another one.")
            return
        }
        AppAnimation.with(AppAnimation.liftFly) {
            sticker = lifted
            stickerIsNew = true
        }
        Haptics.success()
        status = nil
        if AIDataConsent.isGranted {
            await read(lifted)
        } else {
            showConsent = true
        }
    }

    private func readAfterConsent() {
        guard AIDataConsent.isGranted, let sticker else { return }
        Task { await read(sticker) }
    }

    /// Names the product and fills its macros from the cut-out. Typed
    /// fields win: only empty ones are filled.
    private func read(_ sticker: UIImage) async {
        guard MealScanQuota.remainingThisWeek(isPro: storeService.isProUser) != 0 else {
            status = String(localized: "This week's free scans are used up. Type the name yourself.")
            return
        }
        isReading = true
        status = String(localized: "Reading the product…")
        defer { isReading = false }
        do {
            let scan = try await MealScannerService.shared.smartScan(
                image: TableDishReader.flattened(sticker),
                hint: "One grocery product, packaged or fresh, cut out of a photo of a kitchen.",
                metered: true
            )
            if !scan.items.isEmpty, !storeService.isProUser { MealScanQuota.recordSuccessfulScan() }
            guard let found = scan.items.first else { throw MealScannerService.ScanError.noFoodDetected }
            if trimmedName.isEmpty { name = found.name }
            if brand.isEmpty, let foundBrand = found.brand { brand = foundBrand }
            if per100g == nil { per100g = found.per100g }
            status = nil
        } catch MealScannerService.ScanError.scanAllowanceSpent {
            MealScanQuota.recordAllowanceExhausted()
            status = String(localized: "This week's free scans are used up. Type the name yourself.")
        } catch {
            status = String(localized: "Couldn't name it. Type the name yourself.")
        }
    }

    /// A saved product with this barcode fills instantly; otherwise Open
    /// Food Facts does.
    private func lookUp(_ code: String) async {
        if let saved = store.products.first(where: { $0.barcode == code }) {
            fill(from: saved)
            status = nil
            return
        }
        isReading = true
        status = String(localized: "Looking up the barcode…")
        defer { isReading = false }
        do {
            let found = try await OpenFoodFactsService.shared.fetch(barcode: code)
            name = found.name
            brand = found.brand ?? ""
            if let grams = found.packageGrams { amount = "\(Int(grams.rounded())) g" }
            per100g = found.nutritionMissing ? per100g : found.per100g
            imageURL = found.imageURL
            barcode = found.barcode
            keyPicked = false
            matchKey(found.name)
            status = nil
        } catch {
            barcode = code
            status = String(localized: "That barcode isn't in Open Food Facts. Name it yourself or take a photo.")
        }
    }

    // MARK: - Saving

    private func save() {
        var saved = product ?? FridgeProduct(name: trimmedName)
        saved.name = trimmedName
        saved.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        saved.amount = amount.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        saved.place = place
        saved.pantryKey = pantryKey
        saved.per100g = per100g
        saved.imageURL = imageURL
        saved.barcode = barcode
        let date = hasDate ? calendar.startOfDay(for: expiresOn) : nil
        let photo = stickerIsNew ? sticker : nil

        if var item {
            store.update(saved, photo: photo)
            item.count = count
            item.place = place
            item.expiresOn = date
            store.update(item)
        } else {
            store.add(saved, photo: photo, count: count, place: place, expiresOn: date)
        }
        Haptics.success()
        if date != nil { Task { await askForReminders() } }
        onClose()
    }

    /// Asks once; a no keeps the coloured badges doing the reminding.
    private func askForReminders() async {
        guard await NotificationService.shared.checkAuthorization() == .notDetermined,
              await NotificationService.shared.requestAuthorization() else { return }
        await FridgeReminderScheduler.reconcile(items: store.items, products: store.productsByID)
    }
}
