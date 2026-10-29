import PhotosUI
import SwiftUI

/// Scan a whole fridge, shelf or shopping haul in one shot.
///
/// 1. "What's in the fridge?" — a live viewfinder inside the sheet.
/// 2. The photo goes to the fridge scan, which names every product and
///    says where it sits, while a scan band sweeps the photo.
/// 3. "Look at all that." — each product is cut out on-device, the photo
///    breaks into pixels and the cut-outs float to their own cards, the
///    way the table scan lifts dishes. Each card can be left out,
///    renamed, recounted, moved to the freezer or re-dated.
/// 4. "Put in N items" stores them, saving every product for one-tap
///    re-adds.
struct FridgeScanFlow: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onDone: (Int) -> Void
    let onClose: () -> Void

    private enum Phase: Equatable { case capture, reading, review, failed }
    private enum PendingAction { case shutter, library }
    private enum CameraState { case starting, live, denied, unavailable }

    @State private var phase: Phase = .capture
    @State private var photo: UIImage?
    @State private var groceries: [ReviewGrocery] = []
    @State private var landed: Set<UUID> = []
    @State private var dissolveStart: Date?
    @State private var dissolved = false
    @State private var cardSize: CGSize = .zero
    @State private var errorText: String?

    @State private var camera = TableCamera()
    @State private var cameraState: CameraState = .starting
    @State private var isCameraInterrupted = false
    @State private var isShowingLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var pendingAction: PendingAction?
    @State private var showConsent = false
    @State private var showScanLimitPaywall = false
    @State private var storeService = StoreService.shared
    @State private var work: Task<Void, Never>?
    @State private var shutterCount = 0
    @State private var isSweeping = false
    @State private var confirmsDiscard = false
    @State private var isFinished = false
    @Namespace private var lift

    private var store: FridgeStore { FridgeStore.shared }

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
        .accessibilityIdentifier("fridge-scan-flow")
        .appAnimation(AppAnimation.step, value: phase)
        .interactiveDismissDisabled(phase == .reading || phase == .review)
        .task { await startCamera() }
        .onDisappear {
            work?.cancel()
            camera.stop()
        }
        .onReceive(camera.interruptions) { isCameraInterrupted = $0 }
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            libraryItem = nil
            work?.cancel()
            work = Task { await importPhoto(item) }
        }
        .photosPicker(isPresented: $isShowingLibrary, selection: $libraryItem, matching: .images, photoLibrary: .shared())
        .sheet(isPresented: $showConsent, onDismiss: resumeAfterConsent) {
            AIConsentSheet(whatIsSent: "The photo of your fridge or shopping you take or pick.")
                .liquidGlassPresentation()
        }
        .confirmationDialog("Discard this scan?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard scan", role: .destructive) { close() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nothing will be put in your fridge.")
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
                Text(phase == .review ? "Look at all that." : "What's in the fridge?")
                    .font(AppFont.title2)
                    .foregroundStyle(AppColor.textPrimary)
                    .contentTransition(.opacity)
                Text(phase == .review ? "Tap anything you don't want to keep." : "Open the door, or lay out your shopping.")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
            GlassIconButton(icon: "xmark", accessibilityLabel: "Close", size: 32) { requestClose() }
        }
    }

    // MARK: - Stage

    @ViewBuilder
    private func stage(in size: CGSize) -> some View {
        let card = CGSize(width: size.width, height: min(size.height, size.width * 1.3))
        switch phase {
        case .capture:
            viewfinder
                .frame(width: card.width, height: card.height)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
        case .reading:
            readingCard
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
            case .starting:
                ProgressView()
            case .denied:
                cameraMessage("Camera access is off for Atlas. Turn it on in Settings, or import a photo.", settings: true)
            case .unavailable:
                cameraMessage("No camera here. Import a photo of your fridge instead.", settings: false)
            }
        }
        .overlay { shutterFlash }
    }

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

    private var readingCard: some View {
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
                    Text("Taking stock…")
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
        .motionAwareLoop(AppAnimation.breathe, autoreverses: true, isRunning: $isSweeping)
        .onDisappear { isSweeping = false }
    }

    private var reviewGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.md), GridItem(.flexible(), spacing: Spacing.md)],
                      spacing: Spacing.xl) {
                ForEach($groceries) { $grocery in
                    FridgeScanCell(grocery: $grocery, isLanded: landed.contains(grocery.id), namespace: lift)
                }
            }
            .padding(.vertical, Spacing.sm)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var flyingLayer: some View {
        ZStack(alignment: .topLeading) {
            if !dissolved, let photo {
                PixelDissolve(image: photo, startedAt: dissolveStart)
                    .frame(width: cardSize.width, height: cardSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
            }
            if let photo {
                ForEach(groceries.filter { !landed.contains($0.id) }) { grocery in
                    let rect = TableStageLayout.place(grocery.frame, photo: photo.size, card: cardSize)
                    Image(uiImage: grocery.sticker)
                        .resizable()
                        .scaledToFit()
                        .frame(width: rect.width, height: rect.height)
                        .matchedGeometryEffect(id: grocery.id, in: lift)
                        .appShadow(AppShadow.glassElevated)
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
            Image(systemName: "refrigerator")
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
        case .capture, .reading:
            captureControls
        case .review:
            VStack(spacing: Spacing.sm) {
                GlassButton(title: keepTitle, style: .primary, isFullWidth: true) { keep() }
                    .disabled(keptCount == 0)
                Button("Discard") { requestClose() }
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(minHeight: Spacing.minimumHitTarget)
            }
        case .failed:
            GlassButton(title: "Try again", icon: "camera", style: .primary, isFullWidth: true) { restart() }
        }
    }

    private var captureControls: some View {
        VStack(spacing: Spacing.md) {
            Text(captionText)
                .font(AppFont.caption2)
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
                            .font(AppFont.caption2)
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
                        .opacity(canShoot ? 1 : 0.4)
                }
                .buttonStyle(ScalePressStyle(pressedScale: 0.9))
                .disabled(!canShoot)
                .accessibilityLabel("Take photo")

                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            }
            .disabled(phase != .capture)
        }
    }

    private var captionText: LocalizedStringKey {
        guard !storeService.isProUser, let left = MealScanQuota.remainingThisWeek(isPro: false) else {
            return "One photo of the whole shelf or bag."
        }
        return "One photo of the whole shelf or bag. \(left) free scans left this week."
    }

    private var keptCount: Int { groceries.filter(\.include).count }

    private var keepTitle: LocalizedStringKey {
        if keptCount == 1 { return "Put in 1 item" }
        return "Put in \(keptCount) items"
    }

    private var canShoot: Bool { cameraState == .live && !isCameraInterrupted && phase == .capture }

    // MARK: - Camera

    private func startCamera() async {
        guard TableCamera.isAvailable else {
            cameraState = .unavailable
            return
        }
        switch await CameraAuthorization.resolve() {
        case .granted:
            cameraState = camera.start() ? .live : .unavailable
        case .denied, .restricted:
            cameraState = .denied
        }
    }

    /// The photo goes to Anthropic and costs a free scan, so the allowance
    /// and the one-time consent are checked before the shot.
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
            await read(image)
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            errorText = String(localized: "Couldn't open that photo. Try another one.")
            phase = .failed
            return
        }
        await read(image)
    }

    // MARK: - Reading

    private func read(_ image: UIImage) async {
        camera.stop()
        guard let upright = FridgeLiftEngine.prepare(image) else {
            errorText = String(localized: "Couldn't open that photo. Try another one.")
            phase = .failed
            return
        }
        let shot = UIImage(cgImage: upright)
        photo = shot
        groceries = []
        landed = []
        dissolveStart = nil
        dissolved = false
        phase = .reading
        do {
            let keys = Array(Set(RecipeLibraryEngine.bundled.flatMap(\.pantryKeys))).sorted()
            let found = try await FridgeScanService.scan(shot, pantryKeys: keys)
            try Task.checkCancellation()
            if !storeService.isProUser { MealScanQuota.recordSuccessfulScan() }
            let stickers = await FridgeLiftEngine.lift(found.map(\.box), from: upright)
            try Task.checkCancellation()
            groceries = zip(found, stickers).map { ReviewGrocery($0, sticker: $1, saved: savedMatch(for: $0)) }
            phase = .review
            Haptics.success()
            try await Task.sleep(for: .milliseconds(350))
            land()
        } catch MealScannerService.ScanError.scanAllowanceSpent {
            MealScanQuota.recordAllowanceExhausted()
            phase = .capture
            camera.start()
            showScanLimitPaywall = true
        } catch MealScannerService.ScanError.noFoodDetected {
            errorText = String(localized: "Couldn't spot any groceries. Get the shelves in frame with the door wide open, or lay your shopping out.")
            phase = .failed
            Haptics.error()
        } catch {
            guard !Task.isCancelled else { return }
            errorText = error.localizedDescription
            phase = .failed
            Haptics.error()
        }
    }

    /// A product bought before, so its last shelf life and picture carry over.
    private func savedMatch(for found: FridgeScanService.Found) -> FridgeProduct? {
        let candidate = FridgeProduct(name: found.name, brand: found.brand)
        return store.products.first { FridgeStore.isSame($0, candidate) }
    }

    private func land() {
        guard !reduceMotion else {
            landed = Set(groceries.map(\.id))
            dissolved = true
            return
        }
        dissolveStart = Date()
        for (index, grocery) in groceries.enumerated() {
            AppAnimation.with(AppAnimation.liftFly.delay(Double(index) * AppAnimation.liftStagger)) {
                _ = landed.insert(grocery.id)
            }
        }
        Task {
            try? await Task.sleep(for: PixelDissolve.duration)
            dissolved = true
        }
    }

    private func restart() {
        work?.cancel()
        photo = nil
        groceries = []
        errorText = nil
        phase = .capture
        camera.start()
    }

    // MARK: - Finishing

    private func keep() {
        guard !isFinished else { return }
        isFinished = true
        let kept = groceries.filter(\.include)
        for grocery in kept {
            store.add(grocery.product, photo: grocery.sticker, count: grocery.count, place: grocery.place, expiresOn: grocery.expiresOn)
        }
        Haptics.success()
        onDone(kept.count)
    }

    /// A scan already cost a free scan, so it isn't thrown away on one tap.
    private func requestClose() {
        if phase == .review && !groceries.isEmpty {
            confirmsDiscard = true
        } else {
            close()
        }
    }

    private func close() {
        isFinished = true
        onClose()
    }
}
