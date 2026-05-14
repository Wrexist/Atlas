import SwiftUI

/// Full-screen, paginated viewer for the local progress-photo library.
/// Opens at `initialFilename` and lets the user swipe through every
/// photo on `dataStore.profile.progressPhotoFilenames`, sorted newest
/// first so the most recent capture is the default entry point.
///
/// Privacy: photos stay strictly on-device — the share sheet hands off
/// the JPEG URL via UIActivityViewController, which respects the system
/// app picker (AirDrop, Messages, Photos.app) but doesn't upload to
/// PeptideX servers. Same guarantee as the rest of the feature.
struct ProgressPhotoDetailView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    /// Initial photo to open. Used to seed the paginated `TabView`'s
    /// selection; after that the user drives navigation by swiping.
    let initialFilename: String

    @State private var currentFilename: String
    @State private var pendingDeletion: String?
    @State private var sharingURL: ShareItem?

    init(initialFilename: String) {
        self.initialFilename = initialFilename
        _currentFilename = State(initialValue: initialFilename)
    }

    /// Newest-first slice so the timeline reads chronologically as the
    /// user swipes left-to-right backward through time. Older photos
    /// land at the end of the page indicator.
    private var orderedFilenames: [String] {
        dataStore.profile.progressPhotoFilenames.reversed()
    }

    private var currentIndex: Int {
        orderedFilenames.firstIndex(of: currentFilename) ?? 0
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if orderedFilenames.isEmpty {
                emptyState
            } else {
                pagedPhotos
            }
        }
        .navigationTitle(dateLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.black.opacity(0.6), for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    presentShareSheet()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share photo")
                .disabled(orderedFilenames.isEmpty)

                Button(role: .destructive) {
                    pendingDeletion = currentFilename
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete photo")
                .disabled(orderedFilenames.isEmpty)
            }
        }
        .confirmationDialog(
            "Delete this photo?",
            isPresented: deletionBinding,
            presenting: pendingDeletion
        ) { filename in
            Button("Delete", role: .destructive) { delete(filename: filename) }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { _ in
            Text("Removed from this device. Progress photos are not synced anywhere.")
        }
        .sheet(item: $sharingURL) { item in
            ShareSheet(url: item.url)
        }
    }

    // MARK: - Paged content

    private var pagedPhotos: some View {
        TabView(selection: $currentFilename) {
            ForEach(orderedFilenames, id: \.self) { filename in
                photoPage(for: filename)
                    .tag(filename)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .indexViewStyle(.page(backgroundDisplayMode: .never))
        .overlay(alignment: .bottom) {
            if orderedFilenames.count > 1 {
                pageIndicator
                    .padding(.bottom, Spacing.xl)
            }
        }
    }

    private func photoPage(for filename: String) -> some View {
        Group {
            if let image = ProgressPhotoStorage.loadImage(for: filename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Progress photo from \(detailedDate(for: filename))")
            } else {
                missingPhotoPlaceholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            Text("\(currentIndex + 1) of \(orderedFilenames.count)")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(.black.opacity(0.55))
                .overlay {
                    Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                }
        }
        .accessibilityElement()
        .accessibilityLabel("Photo \(currentIndex + 1) of \(orderedFilenames.count)")
    }

    private var missingPhotoPlaceholder: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.5))
            Text("This photo is no longer on this device.")
                .font(AppFont.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.xl)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "camera")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.5))
            Text("No progress photos yet")
                .font(AppFont.headline)
                .foregroundStyle(.white)
            Text("Add a photo from the Lifestyle tab to start a timeline.")
                .font(AppFont.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.xl)
    }

    // MARK: - Title / date

    private var dateLabel: String {
        guard let date = timestamp(from: currentFilename) else { return "Photo" }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func detailedDate(for filename: String) -> String {
        guard let date = timestamp(from: filename) else { return "an unknown date" }
        return date.formatted(.dateTime.month(.wide).day().year())
    }

    /// Parses the timestamp out of a `progress-<unix>-<uuid6>.jpg`
    /// filename. Returns nil for legacy filenames that don't fit the
    /// pattern so the title falls back to a generic label rather than
    /// crashing the navigation bar.
    private func timestamp(from filename: String) -> Date? {
        let components = filename.split(separator: "-")
        guard components.count >= 2, let seconds = TimeInterval(components[1]) else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
    }

    // MARK: - Actions

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { newValue in
                if !newValue { pendingDeletion = nil }
            }
        )
    }

    private func delete(filename: String) {
        let wasLast = orderedFilenames.count == 1
        // Capture neighbour BEFORE mutating profile so we can land on the
        // adjacent photo after deletion instead of resetting to index 0.
        let neighbour = orderedFilenames.first { $0 != filename }
        ProgressPhotoStorage.delete(filename: filename)
        dataStore.removeProgressPhotoFilename(filename)
        pendingDeletion = nil
        if dataStore.profile.hapticFeedbackEnabled {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        if wasLast {
            dismiss()
        } else if let neighbour {
            currentFilename = neighbour
        }
    }

    private func presentShareSheet() {
        guard let url = try? ProgressPhotoStorage.url(for: currentFilename) else { return }
        sharingURL = ShareItem(url: url)
    }
}

// MARK: - Share helpers

/// `.sheet(item:)` requires Identifiable. Wrap the URL so SwiftUI can
/// uniquely identify each presentation by the underlying filename.
private struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.lastPathComponent }
}

/// Minimal UIKit bridge to the system share sheet. SwiftUI's
/// ShareLink is the modern preference, but it requires a Transferable
/// payload up front — here we want to honor the same file URL the
/// user already trusts on-device, which UIActivityViewController takes
/// directly.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        ProgressPhotoDetailView(initialFilename: "progress-1700000000-abc123.jpg")
            .environment(DataStore(seedSampleData: true))
    }
    .preferredColorScheme(.dark)
}
