import SwiftUI
import PhotosUI

/// 2×2 grid of the most-recent progress photos. Photos are stored
/// strictly on-device under `Documents/ProgressPhotos/` and are never
/// uploaded anywhere — privacy guarantee surfaced in the card copy.
///
/// Each populated tile renders the photo with a heavy blur by default;
/// a tap toggles the blur off so the user can review without the photo
/// being immediately visible from across the room. Long-press surfaces
/// a delete action.
struct ProgressPhotosCard: View {
    @Environment(DataStore.self) private var dataStore

    @State private var pickerItem: PhotosPickerItem?
    @State private var revealedFilename: String?
    @State private var pendingDelete: String?
    @State private var errorText: String?

    private static let slotCount = 4

    /// Newest-first slice of the most recent four filenames so the grid
    /// fills top-left → bottom-right with the latest photos.
    private var recentFilenames: [String] {
        Array(dataStore.profile.progressPhotoFilenames.suffix(Self.slotCount).reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Spacing.sm),
                    GridItem(.flexible(), spacing: Spacing.sm),
                ],
                spacing: Spacing.sm
            ) {
                ForEach(0..<Self.slotCount, id: \.self) { index in
                    photoSlot(filename: recentFilenames.safe(index))
                }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .liquidGlass(.rect(cornerRadius: Spacing.cardCornerRadius))
        .onChange(of: pickerItem) { _, newValue in
            Task { await loadAndPersist(item: newValue) }
        }
        .alert(
            "Delete this photo?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { filename in
            Button("Delete", role: .destructive) { delete(filename: filename) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Removed from this device. Progress photos are not synced anywhere.")
        }
        .alert(
            "Couldn't save photo",
            isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Label {
                Text("Progress Photos")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
            } icon: {
                Image(systemName: "camera.fill")
                    .foregroundStyle(AppColor.accentPrimary)
            }

            Spacer(minLength: 0)

            PhotosPicker(
                selection: $pickerItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Add photo")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(AppColor.accentLight)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 6)
                .background {
                    Capsule(style: .continuous)
                        .fill(AppColor.accentPrimary.opacity(0.18))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                        }
                }
                .liquidGlass(.capsule)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func photoSlot(filename: String?) -> some View {
        if let filename, let image = ProgressPhotoStorage.loadImage(for: filename) {
            populatedSlot(filename: filename, image: image)
        } else {
            emptySlot
        }
    }

    private func populatedSlot(filename: String, image: UIImage) -> some View {
        let isRevealed = revealedFilename == filename
        return Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .blur(radius: isRevealed ? 0 : 18)
            .overlay(alignment: .topTrailing) {
                if !isRevealed {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(6)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(AppAnimation.springSnappy) {
                    revealedFilename = isRevealed ? nil : filename
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            .contextMenu {
                Button(role: .destructive) {
                    pendingDelete = filename
                } label: {
                    Label("Delete photo", systemImage: "trash")
                }
            }
    }

    private var emptySlot: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceElevated)
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }

            Image(systemName: "photo")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(AppColor.textTertiary.opacity(0.6))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
            .fill(AppColor.surfaceSecondary.opacity(0.6))
            .overlay {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
            }
    }

    // MARK: - Picker → disk

    @MainActor
    private func loadAndPersist(item: PhotosPickerItem?) async {
        defer { pickerItem = nil }
        guard let item else { return }
        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                errorText = "Couldn't read that photo. Try a different one."
                return
            }
            let filename = try ProgressPhotoStorage.save(image)
            dataStore.addProgressPhotoFilename(filename)
            if dataStore.profile.hapticFeedbackEnabled {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if dataStore.profile.hapticFeedbackEnabled {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func delete(filename: String) {
        ProgressPhotoStorage.delete(filename: filename)
        dataStore.removeProgressPhotoFilename(filename)
        if revealedFilename == filename { revealedFilename = nil }
        if dataStore.profile.hapticFeedbackEnabled {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}

private extension Array where Element == String {
    func safe(_ index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
