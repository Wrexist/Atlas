import SwiftUI

/// Side-by-side comparison of two progress photos. Top row shows
/// both photos at equal width, captioned with their dates and the
/// gap between them. The user can pick the other photo from a
/// horizontally-scrolling thumbnail strip below, so jumping
/// between "compare to last week vs. compare to 3 months ago" is
/// a one-tap swap.
///
/// The two-photo split is the most-shared image users post in
/// recovery / optimisation communities. Sharing isn't wired in
/// this commit — that's a follow-up for a future "share card"
/// feature — but the layout is designed so a screenshot reads
/// well on its own.
struct ProgressPhotoCompareView: View {
    let allFilenames: [String]              // chronological, oldest-first
    let primary: String                     // user came in with this photo selected
    let onClose: () -> Void

    @State private var compareWith: String?
    @State private var blurEnabled: Bool = false

    /// Default the comparison target to the photo furthest from
    /// `primary` chronologically — the most striking comparison
    /// is usually "today vs. the oldest one I've got".
    private var defaultCompareWith: String? {
        guard allFilenames.count >= 2 else { return nil }
        guard let primaryIndex = allFilenames.firstIndex(of: primary) else {
            return allFilenames.first
        }
        // Pick whichever endpoint is further away than the primary.
        let distanceToFirst = primaryIndex
        let distanceToLast = (allFilenames.count - 1) - primaryIndex
        return distanceToFirst > distanceToLast
            ? allFilenames.first
            : allFilenames.last
    }

    private var resolvedCompare: String? {
        compareWith ?? defaultCompareWith
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: Spacing.md) {
                    photoPair
                    if let compare = resolvedCompare {
                        diffStrip(primary: primary, compare: compare)
                    }
                    Divider().background(AppColor.glassBorder)
                    pickerStrip
                    Spacer(minLength: 0)
                }
                .padding(.top, Spacing.md)
                .padding(.horizontal, Spacing.md)
            }
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                        .foregroundStyle(AppColor.textPrimary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            blurEnabled.toggle()
                        }
                    } label: {
                        Image(systemName: blurEnabled ? "eye.slash.fill" : "eye.fill")
                            .foregroundStyle(AppColor.accentLight)
                    }
                    .accessibilityLabel(blurEnabled ? "Reveal photos" : "Blur photos")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Photo pair

    private var photoPair: some View {
        HStack(spacing: Spacing.sm) {
            photoColumn(filename: resolvedCompare, label: olderLabel)
            photoColumn(filename: primary, label: newerLabel)
        }
        .frame(maxHeight: 360)
    }

    private var olderLabel: String {
        guard let compare = resolvedCompare else { return "Before" }
        return ProgressPhotoMetadata.displayDate(forFilename: compare)
    }

    private var newerLabel: String {
        ProgressPhotoMetadata.displayDate(forFilename: primary)
    }

    @ViewBuilder
    private func photoColumn(filename: String?, label: String) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(AppFont.scaled(11, weight: .heavy))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.textSecondary)
            if let filename, let image = ProgressPhotoStorage.loadImage(for: filename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: blurEnabled ? 18 : 0)
                    .animation(.easeOut(duration: 0.18), value: blurEnabled)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.65))
            Image(systemName: "photo")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AppColor.textTertiary)
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
    }

    // MARK: - Diff caption

    private func diffStrip(primary: String, compare: String) -> some View {
        let days = ProgressPhotoMetadata.daysBetween(primary, compare)
        return HStack(spacing: Spacing.sm) {
            Image(systemName: "calendar.badge.clock")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
            Text(diffCopy(days: days))
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.accentPrimary.opacity(0.18))
        }
    }

    private func diffCopy(days: Int) -> LocalizedStringResource {
        switch days {
        case 0:
            return LocalizedStringResource("Same day", comment: "Compare-photos diff caption when both photos are from today.")
        case 1:
            return LocalizedStringResource("1 day apart")
        case 2..<7:
            return LocalizedStringResource("\(days) days apart")
        case 7..<30:
            let weeks = days / 7
            return weeks == 1
                ? LocalizedStringResource("1 week apart")
                : LocalizedStringResource("\(weeks) weeks apart")
        case 30..<365:
            let months = days / 30
            return months == 1
                ? LocalizedStringResource("1 month apart")
                : LocalizedStringResource("\(months) months apart")
        default:
            let years = days / 365
            return years == 1
                ? LocalizedStringResource("1 year apart")
                : LocalizedStringResource("\(years) years apart")
        }
    }

    // MARK: - Picker strip

    private var pickerStrip: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Compare with")
                .font(AppFont.scaled(11, weight: .heavy))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(otherFilenames, id: \.self) { filename in
                        thumbnailButton(filename: filename)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
        }
    }

    /// All photos except the primary one — the comparison target
    /// list. Keep them in chronological order so the user reads
    /// "oldest → newest" left to right.
    private var otherFilenames: [String] {
        allFilenames.filter { $0 != primary }
    }

    private func thumbnailButton(filename: String) -> some View {
        let active = filename == resolvedCompare
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                compareWith = filename
            }
            Haptics.impact(.light)
        } label: {
            VStack(spacing: 4) {
                if let image = ProgressPhotoStorage.loadImage(for: filename) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: blurEnabled ? 8 : 0)
                        .frame(width: 56, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                .strokeBorder(
                                    active ? AppColor.accentLight : AppColor.glassBorder,
                                    lineWidth: active ? 2 : 0.5
                                )
                        }
                } else {
                    placeholder.frame(width: 56, height: 70)
                }
                Text(ProgressPhotoMetadata.displayDate(forFilename: filename))
                    .font(AppFont.scaled(8, weight: .semibold))
                    .foregroundStyle(active ? AppColor.accentLight : AppColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 60)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Compare with \(ProgressPhotoMetadata.displayDate(forFilename: filename))")
    }
}
