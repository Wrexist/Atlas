import Photos
import PhotosUI
import SwiftUI

/// Scan a whole table in one shot.
///
/// 1. "What's on the table?" — a live viewfinder inside the sheet.
/// 2. The dishes are cut out on-device (`TableLiftEngine`) while the
///    photo shimmers.
/// 3. "Nice table." — the photo breaks into pixels and every cut-out
///    flies to its own card, where the scan names it and the user can
///    leave it out, sort it, rename it, or cut a missed one by hand.
/// 4. Keep hands the kept dishes to the caller, which logs them and
///    shows the table.
///
/// Swiping the sheet down once every dish is read counts as Keep, the
/// way the footer says.
struct TableScanFlow: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Day the Meals screen was showing when the scan started.
    var logDay: Date = Date()
    /// Set to add more dishes to a table already on file.
    var addingTo: TableMoment?
    let onKeep: (TableMomentStore.Draft) -> Void
    let onClose: () -> Void

    private enum Phase: Equatable { case capture, lifting, review, failed }
    private enum PendingAction { case shutter, library }
    private enum CameraState { case starting, live, denied, unavailable }

    @State private var phase: Phase = .capture
    @State private var photo: UIImage?
    /// When an imported photo was taken; nil for a shot from the viewfinder.
    @State private var capturedAt: Date?
    @State private var dishes: [ReviewDish] = []
    @State private var landed: Set<UUID> = []
    @State private var dissolveStart: Date?
    @State private var dissolved = false
    @State private var cardSize: CGSize = .zero
    @State private var errorText: String?

    @State private var camera = TableCamera()
    @State private var cameraState: CameraState = .starting
    @State private var lens: TableCamera.Lens = .table
    @State private var showsGrid = false
    @AppStorage("tableScan.saveOriginal") private var saveOriginal = false
    @State private var photosAccessDenied = false
    @State private var isShowingLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var isCutting = false

    @State private var pendingAction: PendingAction?
    @State private var showConsent = false
    @State private var showScanLimitPaywall = false
    @State private var storeService = StoreService.shared
    @State private var hasSpentScan = false

    @State private var work: Task<Void, Never>?
    /// Every queue still reading — each new batch waits on the one before,
    /// so all of them are cancelled together.
    @State private var readQueues: [Task<Void, Never>] = []
    @State private var isFinished = false
    @State private var shutterCount = 0
    @State private var isSweeping = false
    @State private var confirmsDiscard = false
    @Namespace private var lift
    @Namespace private var lensPill

    /// Readings the proxy is asked for at once. Eight plates fired together
    /// trip its per-device rate limit.
    private static let concurrentReads = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    stage(in: geo.size)
                    if phase == .review { flyingLayer }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
            footer
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.lg)
        .background(AppColor.background)
        .accessibilityIdentifier("table-scan-flow")
        .appAnimation(AppAnimation.step, value: phase)
        .interactiveDismissDisabled(phase == .lifting || isReading)
        .task { await startCamera() }
        .onDisappear(perform: finishOnDismiss)
        .onChange(of: lens) { _, lens in camera.frame(lens) }
        .onChange(of: saveOriginal) { _, on in
            if on { Task { _ = await confirmPhotosAccess() } }
        }
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            libraryItem = nil
            work?.cancel()
            work = Task { await importPhoto(item) }
        }
        .photosPicker(isPresented: $isShowingLibrary, selection: $libraryItem, matching: .images, photoLibrary: .shared())
        .sheet(isPresented: $isCutting) {
            if let photo {
                CutItOutSheet(photo: photo, onCut: addHandCut)
                    .liquidGlassPresentation()
            }
        }
        .sheet(isPresented: $showConsent, onDismiss: resumeAfterConsent) {
            AIConsentSheet(whatIsSent: "A cut-out of each dish on the table you photograph.")
                .liquidGlassPresentation()
        }
        .confirmationDialog("Discard this table?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard table", role: .destructive) { close() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your dishes won't be logged.")
        }
        .alert("Photos access is off", isPresented: $photosAccessDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow Atlas to add photos in Settings to save your originals.")
        }
        .sheet(isPresented: $showScanLimitPaywall) {
            PaywallView(source: .mealScanLimit)
                .environment(dataStore)
                .liquidGlassPresentation()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(phase == .review ? "Nice table." : "What's on the table?")
                    .font(AppFont.title2)
                    .foregroundStyle(AppColor.textPrimary)
                    .contentTransition(.opacity)
                if phase == .review {
                    Text("Tap anything you don't want to keep.")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 0)
            GlassIconButton(icon: "xmark", accessibilityLabel: "Close", size: 32) { requestClose() }
        }
    }

    // MARK: - Stage

    @ViewBuilder
    private func stage(in size: CGSize) -> some View {
        let card = CGSize(width: size.width, height: min(size.height, size.width * 1.2))
        switch phase {
        case .capture:
            viewfinder
                .frame(width: card.width, height: card.height)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
        case .lifting:
            liftingCard
                .frame(width: card.width, height: card.height)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
                .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }
        case .review:
            reviewGrid
        case .failed:
            failure
        }
    }

    private var viewfinder: some View {
        ZStack {
            AppColor.surfaceSecondary
            switch cameraState {
            case .live:
                TableCameraPreview(camera: camera)
                if showsGrid { thirdsGrid }
            case .starting:
                ProgressView()
            case .denied:
                cameraMessage("Camera access is off for Atlas. Turn it on in Settings, or import a photo.", settings: true)
            case .unavailable:
                cameraMessage("No camera here. Import a photo of the table instead.", settings: false)
            }
        }
        .overlay(alignment: .topLeading) {
            if cameraState == .live {
                Button {
                    showsGrid.toggle()
                    Haptics.selection()
                } label: {
                    Label("Grid", systemImage: "square.grid.3x3")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textPrimary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .glassControl(.capsule, tint: showsGrid ? AppColor.accentPrimary.opacity(0.18) : nil)
                }
                .buttonStyle(.plain)
                .minimumHitArea()
                .padding(Spacing.md)
                .accessibilityAddTraits(showsGrid ? .isSelected : [])
            }
        }
        .overlay(alignment: .bottom) {
            if cameraState == .live { lensPicker.padding(.bottom, Spacing.lg) }
        }
        .overlay { shutterFlash }
    }

    /// A quick white blink when the shutter fires, so the shot reads as
    /// taken before the lifting starts.
    private var shutterFlash: some View {
        AppColor.onAccent
            .keyframeAnimator(initialValue: 0.0, trigger: shutterCount) { flash, value in
                flash.opacity(value)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(0.85, duration: 0.04)
                    CubicKeyframe(0, duration: 0.32)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var lensPicker: some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(TableCamera.Lens.allCases) { option in
                Button {
                    lens = option
                    Haptics.selection()
                } label: {
                    Text(option.label)
                        .font(AppFont.caption)
                        .fontWeight(lens == option ? .semibold : .regular)
                        .foregroundStyle(lens == option ? AppColor.textPrimary : AppColor.textSecondary)
                        .padding(.horizontal, Spacing.md)
                        .frame(minHeight: 32)
                        .background {
                            if lens == option {
                                Capsule()
                                    .fill(AppColor.background)
                                    .matchedGeometryEffect(id: "lens", in: lensPill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .minimumHitArea()
                .accessibilityAddTraits(lens == option ? .isSelected : [])
            }
        }
        .padding(Spacing.xxs)
        .glassControl(.capsule, interactive: false)
        .appAnimation(AppAnimation.springSnappy, value: lens)
    }

    private var thirdsGrid: some View {
        Canvas { context, size in
            var lines = Path()
            for step in 1...2 {
                let x = size.width * CGFloat(step) / 3
                let y = size.height * CGFloat(step) / 3
                lines.move(to: CGPoint(x: x, y: 0))
                lines.addLine(to: CGPoint(x: x, y: size.height))
                lines.move(to: CGPoint(x: 0, y: y))
                lines.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(lines, with: .color(AppColor.onAccent.opacity(0.5)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func cameraMessage(_ text: LocalizedStringKey, settings: Bool) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "camera")
                .font(AppFont.scaled(24, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .accessibilityHidden(true)
            Text(text)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
            if settings {
                GlassButton(title: "Open Settings", style: .secondary) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }
        .padding(Spacing.xl)
    }

    /// `Color.clear` takes the card's size and the photo fills it from an
    /// overlay, so the crop stays centred the way `TableStageLayout`
    /// assumes and the pill sits on the card, not the overflow.
    private var liftingCard: some View {
        Color.clear
            .overlay {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay { scanSweep }
            .overlay(alignment: .bottom) {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppColor.accentPrimary)
                    Text("Lifting your dishes…")
                        .font(AppFont.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .glassControl(.capsule, interactive: false)
                .padding(.bottom, Spacing.lg)
            }
    }

    /// A soft band of light sweeping the photo while Vision works — steady,
    /// like a scanner bed, rather than a busy shimmer. Still under Reduce
    /// Motion, where the spinner in the pill carries the wait.
    private var scanSweep: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, AppColor.accentLight.opacity(0.28), AppColor.onAccent.opacity(0.35), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: geo.size.height * 0.22)
            .offset(y: isSweeping ? geo.size.height * 0.85 : -geo.size.height * 0.08)
            .opacity(reduceMotion ? 0 : 1)
        }
        .background(AppColor.background.opacity(0.12))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                isSweeping = true
            }
        }
        .onDisappear { isSweeping = false }
    }

    private var reviewGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.md), GridItem(.flexible(), spacing: Spacing.md)],
                      spacing: Spacing.xl) {
                ForEach($dishes) { $dish in
                    LiftedDishCell(
                        dish: $dish,
                        isLanded: landed.contains(dish.id),
                        namespace: lift,
                        onRetry: { retry(dish.id) }
                    )
                }
            }
            .padding(.vertical, Spacing.sm)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// The photo dissolving and the cut-outs that haven't reached their
    /// cards yet, drawn where the photo card was.
    private var flyingLayer: some View {
        ZStack(alignment: .topLeading) {
            if !dissolved, let photo {
                PixelDissolve(image: photo, startedAt: dissolveStart)
                    .frame(width: cardSize.width, height: cardSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
            }
            if let photo {
                ForEach(dishes.filter { !landed.contains($0.id) }) { dish in
                    let rect = TableStageLayout.place(dish.frame, photo: photo.size, card: cardSize)
                    Image(uiImage: dish.sticker)
                        .resizable()
                        .scaledToFit()
                        .frame(width: rect.width, height: rect.height)
                        .matchedGeometryEffect(id: dish.id, in: lift)
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .frame(width: cardSize.width, height: cardSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var failure: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "fork.knife.circle")
                .font(AppFont.scaled(24, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .symbolEffect(.bounce, value: errorText)
                .accessibilityHidden(true)
            Text(errorText ?? String(localized: "Something went wrong. Try again."))
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        switch phase {
        case .capture, .lifting:
            captureControls
        case .review:
            reviewControls
        case .failed:
            VStack(spacing: Spacing.sm) {
                if photo != nil {
                    GlassButton(title: "Cut it out myself", icon: "scissors", style: .secondary, isFullWidth: true) {
                        isCutting = true
                    }
                }
                GlassButton(title: "Try again", icon: "camera", style: .primary, isFullWidth: true) { restart() }
            }
        }
    }

    private var captureControls: some View {
        VStack(spacing: Spacing.md) {
            Text("One photo of the whole table.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .frame(maxWidth: .infinity)

            HStack(alignment: .center) {
                Button { request(.library) } label: {
                    VStack(spacing: Spacing.xs) {
                        Image(systemName: "photo.on.rectangle")
                            .font(AppFont.scaled(16, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .frame(width: Spacing.minimumHitTarget, height: Spacing.minimumHitTarget)
                            .glassControl(.rect(cornerRadius: Spacing.smallCornerRadius))
                        Text("Import photo")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                .buttonStyle(ScalePressStyle())
                .frame(maxWidth: .infinity)

                Button { request(.shutter) } label: {
                    Circle()
                        .fill(AppColor.accentFill)
                        .padding(Spacing.xs)
                        .overlay { Circle().strokeBorder(AppColor.accentPrimary, lineWidth: 3) }
                        .frame(width: 72, height: 72)
                        .opacity(cameraState == .live && phase == .capture ? 1 : 0.4)
                }
                .buttonStyle(ScalePressStyle(pressedScale: 0.9))
                .disabled(cameraState != .live || phase != .capture)
                .accessibilityLabel("Take photo")

                VStack(spacing: Spacing.xs) {
                    Toggle("Save original", isOn: $saveOriginal)
                        .labelsHidden()
                        .tint(AppColor.accentPrimary)
                    Text("Save original")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Also saves the photo you take to your Photo Library.")
            }
            .disabled(phase != .capture)
        }
    }

    private var reviewControls: some View {
        VStack(spacing: Spacing.sm) {
            GlassButton(title: "Cut it out myself", icon: "scissors", style: .secondary, isFullWidth: true) {
                isCutting = true
            }
            GlassButton(title: keepTitle, style: .primary, isFullWidth: true) { keep() }
                .disabled(isReading || keepableCount == 0)
            Button("Discard") { requestClose() }
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textSecondary)
                .frame(minHeight: Spacing.minimumHitTarget)
            if !isReading && keepableCount > 0 {
                Text("Swipe down anytime — you're done.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
    }

    private var keepTitle: LocalizedStringKey {
        if isReading { return "Reading dishes…" }
        return keepableCount == 1 ? "Keep 1 dish" : "Keep \(keepableCount) dishes"
    }

    private var keepableCount: Int { dishes.filter(\.isKeepable).count }

    private var isReading: Bool { dishes.contains { $0.reading == .pending } }

    // MARK: - Camera

    private func startCamera() async {
        #if DEBUG
        if TableScanFixture.isRequested {
            await playFixture()
            return
        }
        #endif
        guard TableCamera.isAvailable else {
            cameraState = .unavailable
            return
        }
        switch await CameraAuthorization.resolve() {
        case .granted:
            camera.start()
            cameraState = .live
        case .denied, .restricted:
            cameraState = .denied
        }
    }

    /// Every table sends its cut-outs to Anthropic, so the weekly allowance
    /// and the one-time consent are checked before the shot, not after it.
    private func request(_ action: PendingAction) {
        if MealScanQuota.remainingThisWeek(isPro: storeService.isProUser) == 0 {
            showScanLimitPaywall = true
            return
        }
        guard AIDataConsent.isGranted else {
            pendingAction = action
            showConsent = true
            return
        }
        switch action {
        case .library: isShowingLibrary = true
        case .shutter: shoot()
        }
    }

    private func resumeAfterConsent() {
        let action = pendingAction
        pendingAction = nil
        guard AIDataConsent.isGranted, let action else { return }
        request(action)
    }

    private func shoot() {
        Haptics.impact(.medium)
        if !reduceMotion { shutterCount += 1 }
        work?.cancel()
        work = Task {
            guard let image = await camera.capture() else { return }
            capturedAt = nil
            if saveOriginal { Task { await saveToPhotos(image) } }
            await liftDishes(from: image)
        }
    }

    private func saveToPhotos(_ image: UIImage) async {
        guard await confirmPhotosAccess() else { return }
        try? await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }

    /// Turns "Save original" back off and explains why when add-only
    /// Photos access is denied, so the toggle never claims a save that
    /// can't happen.
    private func confirmPhotosAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveOriginal = false
            photosAccessDenied = true
            return false
        }
        return true
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            errorText = String(localized: "Couldn't open that photo. Try another one.")
            phase = .failed
            return
        }
        capturedAt = PhotoCaptureDate.captureDate(fromImageData: data)
        await liftDishes(from: image)
    }

    // MARK: - Lifting

    private func liftDishes(from image: UIImage) async {
        photo = image
        dishes = []
        landed = []
        dissolveStart = nil
        dissolved = false
        phase = .lifting
        camera.stop()
        do {
            let lifted = try await TableLiftEngine.lift(from: image)
            try Task.checkCancellation()
            dishes = lifted.map(ReviewDish.init)
            phase = .review
            Haptics.success()
            readPending()
            try await Task.sleep(for: .milliseconds(350))
            land()
        } catch {
            guard !Task.isCancelled else { return }
            errorText = error.localizedDescription
            phase = .failed
            Haptics.error()
        }
    }

    #if DEBUG
    /// Screenshot runs: the lifting card, then the cut-outs flying to
    /// their cards, with drawn plates standing in for Vision.
    private func playFixture() async {
        photo = TableScanFixture.photo
        phase = .lifting
        try? await Task.sleep(for: .seconds(3))
        dishes = TableScanFixture.reviewDishes()
        phase = .review
        try? await Task.sleep(for: .milliseconds(350))
        land()
    }
    #endif

    /// Sends every cut-out to its card, one after another, as the photo
    /// breaks up behind them.
    private func land() {
        guard !reduceMotion else {
            landed = Set(dishes.map(\.id))
            dissolved = true
            return
        }
        dissolveStart = Date()
        for (index, dish) in dishes.enumerated() {
            AppAnimation.with(AppAnimation.liftFly.delay(Double(index) * AppAnimation.liftStagger)) {
                _ = landed.insert(dish.id)
            }
        }
        Task {
            try? await Task.sleep(for: PixelDissolve.duration)
            dissolved = true
        }
    }

    private func addHandCut(_ circle: CGRect) {
        guard let photo, let lifted = TableLiftEngine.cut(circle, from: photo) else { return }
        dishes.append(ReviewDish(lifted))
        landed.insert(lifted.id)
        if phase != .review {
            dissolved = true
            phase = .review
        }
        readPending()
    }

    private func restart() {
        work?.cancel()
        cancelReads()
        photo = nil
        capturedAt = nil
        dishes = []
        errorText = nil
        phase = .capture
        camera.start()
    }

    // MARK: - Reading

    private func retry(_ id: UUID) {
        guard let index = dishes.firstIndex(where: { $0.id == id }) else { return }
        dishes[index].reading = .pending
        readPending()
    }

    /// Reads every dish still pending, a few at a time.
    private func readPending() {
        let ids = dishes.filter { $0.reading == .pending }.map(\.id)
        guard !ids.isEmpty else { return }
        let previous = readQueues.last
        readQueues.append(Task {
            await previous?.value
            await withTaskGroup(of: Void.self) { group in
                var queue = ids.makeIterator()
                for _ in 0..<Self.concurrentReads {
                    guard let id = queue.next() else { break }
                    group.addTask { @MainActor in await read(id) }
                }
                while await group.next() != nil {
                    guard !Task.isCancelled, let id = queue.next() else { continue }
                    group.addTask { @MainActor in await read(id) }
                }
            }
        })
    }

    private func cancelReads() {
        readQueues.forEach { $0.cancel() }
        readQueues = []
    }

    private func read(_ id: UUID) async {
        // A batch queued behind another may list a dish that one has read.
        guard let dish = dishes.first(where: { $0.id == id }), dish.reading == .pending else { return }
        let result: ReviewDish.Reading
        do {
            let reading = try await TableDishReader.read(dish.sticker, myFoods: dataStore.profile.customFoods)
            result = .read(reading)
            spendScanOnce()
        } catch MealScannerService.ScanError.noFoodDetected {
            result = .notFood
        } catch {
            result = .failed(error.localizedDescription)
        }
        guard !Task.isCancelled, let index = dishes.firstIndex(where: { $0.id == id }) else { return }
        dishes[index].reading = result
        if result == .notFood { dishes[index].include = false }
        if case .read(let reading) = result, reading.kind == .drink {
            dishes[index].kind = .drink
        }
    }

    /// A whole table costs one of the week's free scans, however many
    /// plates were on it.
    private func spendScanOnce() {
        guard !hasSpentScan else { return }
        hasSpentScan = true
        if !storeService.isProUser { MealScanQuota.recordSuccessfulScan() }
    }

    // MARK: - Finishing

    private var logDate: Date {
        if let addingTo { return addingTo.date }
        let shotAt = capturedAt ?? Date()
        let calendar = Calendar.current
        if calendar.isDateInToday(logDay) || calendar.isDate(shotAt, inSameDayAs: logDay) { return shotAt }
        return LifestyleDataLogic.logTimestamp(on: logDay)
    }

    private func draft() -> TableMomentStore.Draft? {
        let date = logDate
        let category = addingTo?.category ?? MealCategory.auto(for: date)
        let kept = dishes.compactMap { dish -> TableMomentStore.Draft.Dish? in
            guard dish.include, case .read(let reading) = dish.reading else { return nil }
            let typed = dish.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let entry = reading.entry(id: dish.id, name: typed.isEmpty ? reading.name : typed, date: date, category: category)
            return .init(entry: entry, kind: dish.kind, sticker: dish.sticker)
        }
        guard !kept.isEmpty else { return nil }
        return .init(momentID: addingTo?.id, date: date, category: category, dishes: kept)
    }

    private func keep() {
        guard !isFinished, let draft = draft() else { return }
        isFinished = true
        onKeep(draft)
    }

    /// Read dishes already cost a scan, so they aren't thrown away on one tap.
    private func requestClose() {
        if dishes.contains(where: { if case .read = $0.reading { true } else { false } }) {
            confirmsDiscard = true
        } else {
            close()
        }
    }

    private func close() {
        isFinished = true
        onClose()
    }

    /// The swipe-down path: a finished review is kept, anything else is
    /// let go.
    private func finishOnDismiss() {
        work?.cancel()
        cancelReads()
        camera.stop()
        guard !isFinished, phase == .review, !isReading, let draft = draft() else { return }
        isFinished = true
        onKeep(draft)
    }
}
