import SwiftUI

/// 2×2 grid of the most-recent progress photos. The actual capture +
/// disk-write flow lives in a follow-up — this iteration ships the
/// surface (placeholder tiles + "+ Add photo" affordance) so the layout
/// matches the spec without introducing image-picker plumbing into the
/// same PR as the Lifestyle layout rebuild.
///
/// When real photos land, the placeholder tiles are replaced by
/// `Image(uiImage: UIImage(contentsOfFile:))` reads against the app's
/// Documents directory using the filenames stored on
/// `profile.progressPhotoFilenames`.
struct ProgressPhotosCard: View {
    let filenames: [String]
    let onAdd: () -> Void

    private static let slotCount = 4

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
                    photoSlot(filename: filenames.dropFirst(max(0, filenames.count - Self.slotCount)).safe(index))
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
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

            Button(action: onAdd) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Add photo")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(AppColor.accentLight)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 4)
                .background {
                    Capsule().fill(AppColor.accentPrimary.opacity(0.15))
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func photoSlot(filename: String?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceElevated)
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }

            if filename == nil {
                Image(systemName: "photo")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(AppColor.textTertiary.opacity(0.6))
            } else {
                // Real capture pipeline lands in a separate task — for now
                // populated slots show a privacy-blur stand-in so the grid
                // shape reads the same once images are wired.
                Image(systemName: "photo.fill")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(AppColor.accentLight.opacity(0.7))
                    .blur(radius: 6)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private extension ArraySlice where Element == String {
    /// Safe indexed access into a sliced collection — the slot count and
    /// the filename count don't always match, and forcing a precondition
    /// would crash on an empty roll. Returns nil for out-of-bounds.
    func safe(_ index: Int) -> Element? {
        let array = Array(self)
        return array.indices.contains(index) ? array[index] : nil
    }
}
