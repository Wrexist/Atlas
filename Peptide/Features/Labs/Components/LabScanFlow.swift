import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers
import UIKit

/// Scan-a-lab-report sheet: collect up to four pages (camera, photo
/// library, or a PDF's pages), send them through `LabScanService`, then
/// hand the transcribed markers to `LabScanReviewView`, where the user
/// confirms each one before anything is saved.
///
/// The Pro gate and the AI-sharing consent are checked by the caller
/// before this sheet opens. Pages live only in this view's state and are
/// dropped when it closes.
struct LabScanFlow: View {
    let sex: BiologicalSex
    /// Called once with every confirmed value; the caller saves each
    /// through the manual-entry path.
    let onSave: ([LabValue]) -> Void
    let onClose: () -> Void

    @State private var pages: [UIImage] = []
    @State private var phase: Phase = .pick
    @State private var errorText: String?
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var isShowingLibrary = false
    @State private var isShowingCamera = false
    @State private var isImportingPDF = false
    @State private var cameraDenied = false
    @State private var discardConfirmation = false
    /// Cancelled on close so an abandoned scan stops spending quota.
    @State private var inFlightTask: Task<Void, Never>?

    private enum Phase: Equatable {
        case pick
        case reading
        case review(LabReportEngine.Scan)
        case error
    }

    private var pagesLeft: Int { LabScanService.maxPages - pages.count }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .pick:             picker
                case .reading:          reading
                case .review(let scan): LabScanReviewView(scan: scan, sex: sex, onSave: onSave)
                case .error:            errorCard
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppColor.background)
            .navigationTitle("Scan lab report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if case .review = phase { discardConfirmation = true } else { close() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(phase != .pick && phase != .error)
        .onDisappear { inFlightTask?.cancel() }
        .confirmationDialog("Discard these results?", isPresented: $discardConfirmation, titleVisibility: .visible) {
            Button("Discard", role: .destructive, action: close)
            Button("Keep reviewing", role: .cancel) {}
        } message: {
            Text("Nothing from this report has been saved yet.")
        }
        .photosPicker(
            isPresented: $isShowingLibrary,
            selection: $libraryItems,
            maxSelectionCount: max(pagesLeft, 1),
            matching: .images
        )
        .onChange(of: libraryItems) { _, items in
            guard !items.isEmpty else { return }
            libraryItems = []
            Task { await addLibraryPages(items) }
        }
        .fileImporter(isPresented: $isImportingPDF, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result { addPDFPages(from: url) }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker(
                onPicked: { image in
                    isShowingCamera = false
                    addPages([image])
                },
                onCancel: { isShowingCamera = false },
                cameraDevice: .rear,
                allowsEditing: false
            )
            .ignoresSafeArea()
        }
        .alert("Camera access off", isPresented: $cameraDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Turn on Camera access for Atlas in Settings to photograph a report. You can still pick photos or a PDF.")
        }
    }

    // MARK: - Phases

    private var picker: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if pages.isEmpty {
                    placeholder
                } else {
                    pageStrip
                }

                Text("Photograph each page of your blood test. Atlas reads every result and you check them before anything is saved.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: Spacing.sm) {
                    if UIImagePickerController.SourceType.cameraIsAvailable {
                        GlassButton(title: "Take photo", icon: "camera.fill", style: .secondary, isFullWidth: true) {
                            Task { await openCamera() }
                        }
                        .disabled(pagesLeft == 0)
                    }
                    GlassButton(title: "Choose photos", icon: "photo.on.rectangle", style: .secondary, isFullWidth: true) {
                        isShowingLibrary = true
                    }
                    .disabled(pagesLeft == 0)
                    GlassButton(title: "Import PDF", icon: "doc.richtext", style: .secondary, isFullWidth: true) {
                        isImportingPDF = true
                    }
                    .disabled(pagesLeft == 0)
                }

                GlassButton(title: "Read report", icon: "text.viewfinder", style: .primary, isFullWidth: true) {
                    startReading()
                }
                .disabled(pages.isEmpty)

                Text("Up to \(LabScanService.maxPages) pages per scan")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(Spacing.xl)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
            .fill(AppColor.surfaceSecondary)
            .frame(height: 160)
            .overlay {
                Image(systemName: "doc.text.viewfinder")
                    .font(AppFont.scaled(48, weight: .light, relativeTo: .largeTitle))
                    .foregroundStyle(AppColor.accentLight)
                    .accessibilityHidden(true)
            }
    }

    private var pageStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.sm) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    Image(uiImage: page)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous))
                        .accessibilityLabel("Page \(index + 1)")
                        .overlay(alignment: .topTrailing) {
                            Button {
                                Haptics.impact(.light)
                                pages.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(AppFont.scaled(20))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(AppColor.onAccent, AppColor.textSecondary)
                            }
                            .minimumHitArea()
                            .accessibilityLabel("Remove page \(index + 1)")
                        }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var reading: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
            Text("Reading ^[\(pages.count) page](inflect: true)…")
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
            // Sets the wait up front, so a long read doesn't look stuck.
            Text("This can take up to a minute. Keep this screen open.")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.xxxxl)
    }

    private var errorCard: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(AppFont.scaled(24))
                .foregroundStyle(AppColor.warning)
                .accessibilityHidden(true)
            Text(errorText ?? String(localized: "Something went wrong."))
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
            GlassButton(title: "Try again", icon: "arrow.clockwise", style: .primary, isFullWidth: true) {
                startReading()
            }
            GlassButton(title: "Change pages", style: .secondary, isFullWidth: true) {
                phase = .pick
            }
        }
        .padding(Spacing.xl)
    }

    // MARK: - Pages

    private func addPages(_ images: [UIImage]) {
        pages.append(contentsOf: images.prefix(pagesLeft))
    }

    private func openCamera() async {
        switch await CameraAuthorization.resolve() {
        case .granted: isShowingCamera = true
        case .denied, .restricted: cameraDenied = true
        }
    }

    private func addLibraryPages(_ items: [PhotosPickerItem]) async {
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                loaded.append(image)
            }
        }
        addPages(loaded)
    }

    /// Renders the PDF's first pages as images — the route reads photos,
    /// and a rendered page is a sharper one than any camera shot.
    private func addPDFPages(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let document = PDFDocument(url: url) else {
            errorText = String(localized: "Couldn't open that PDF. Try a screenshot of the page instead.")
            phase = .error
            return
        }
        let count = min(document.pageCount, pagesLeft)
        let images = (0..<count).compactMap { document.page(at: $0) }.map(Self.render)
        addPages(images)
    }

    /// Long edge 2000 px; the upload step scales down to its own budget.
    private static func render(_ page: PDFPage) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let scale = 2000 / max(bounds.width, bounds.height, 1)
        return page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
    }

    // MARK: - Reading

    private func startReading() {
        guard !pages.isEmpty else { return }
        phase = .reading
        inFlightTask?.cancel()
        let submitted = pages
        inFlightTask = Task { await read(submitted) }
    }

    private func read(_ submitted: [UIImage]) async {
        do {
            let scan = try await LabScanService.shared.scan(pages: submitted)
            guard !Task.isCancelled else { return }
            Haptics.success()
            phase = .review(scan)
        } catch {
            guard !Task.isCancelled else { return }
            Haptics.warning()
            errorText = LabScanService.message(for: error)
            phase = .error
        }
    }

    private func close() {
        inFlightTask?.cancel()
        inFlightTask = nil
        onClose()
    }
}
