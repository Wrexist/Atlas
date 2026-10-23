import SwiftUI
import UIKit
import AVKit

struct WorkoutShareView: View {
    let summary: WorkoutRecapEngine.Summary
    let unit: MeasurementUnit
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Opens on the format the user last shared in.
    @State private var options = WorkoutShareOptions(
        format: ShareFormatMemory.load(ShareFormatMemory.workoutKey, default: .story)
    )
    @State private var model = WorkoutShareController()
    @State private var previewImage: UIImage?
    @State private var previewError: String?
    @State private var previewKey: WorkoutShareRenderKey?
    private var renderKey: WorkoutShareRenderKey {
        WorkoutShareRenderKey(session: summary.session, unit: unit, options: options)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    ShareFormatPicker(options: WorkoutShareFormat.allCases, selection: $options.format)
                        .disabled(model.busy)
                    GlassSegmentedControl(
                        options: WorkoutShareStyle.allCases,
                        selected: $options.style,
                        label: { LocalizedStringKey($0.title) }
                    ).disabled(model.busy).accessibilityIdentifier("workout-share-style")
                    preview
                    Text(options.format.detail).font(AppFont.subheadline).foregroundStyle(AppColor.recapSecondary)
                    if options.style == .highlight && !summary.entries.isEmpty {
                        Picker("Featured exercise", selection: $options.featuredEntryID) {
                            Text("First logged exercise").tag(nil as UUID?)
                            ForEach(summary.entries) { entry in Text(entry.name).tag(Optional(entry.id)) }
                        }.disabled(model.busy).accessibilityIdentifier("workout-share-featured-exercise")
                    }
                    Toggle("Include workout name", isOn: $options.includeName).disabled(model.busy)
                    Toggle("Include date", isOn: $options.includeDate).disabled(model.busy)
                    if summary.volumeKg != nil { Toggle("Include volume", isOn: $options.includeVolume).disabled(model.busy) }
                    Text("Only this card is shared. Private notes, account details and exact times are excluded.")
                        .font(AppFont.subheadline).foregroundStyle(AppColor.recapSecondary)
                    Text("Choose Instagram in Share if available, or save to Photos and select the file in Instagram. Add music and stickers there before posting.")
                        .font(AppFont.subheadline).foregroundStyle(AppColor.recapSecondary)
                }.padding(Spacing.screenPadding)
            }
            .safeAreaInset(edge: .bottom) { actions }
            .recapScreen(title: "Share workout")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Close") { model.cancel(); dismiss() }.minimumHitArea().disabled(model.savingToPhotos)
            } }
            .sheet(item: $model.exportItem) { item in
                ShareSheet(activityItems: [item.url]) { error in model.shareFinished(error: error) }
            }
            .interactiveDismissDisabled(model.busy)
            .onChange(of: renderKey) { _, _ in model.optionsChanged() }
            .onChange(of: options.format) { _, newValue in
                ShareFormatMemory.save(newValue, ShareFormatMemory.workoutKey)
            }
            // The previous card stays up until the new one is ready, then
            // cross-fades — clearing it first flashed a blank frame on
            // every option change.
            .task(id: renderKey) {
                previewError = nil
                await ExerciseLibrary.shared.load()
                guard !Task.isCancelled else { return }
                do {
                    let image = try WorkoutSocialRenderer.image(summary: summary, unit: unit, options: options)
                    AppAnimation.with(AppAnimation.quick) {
                        previewImage = image
                        previewKey = renderKey
                    }
                } catch {
                    previewImage = nil
                    previewError = "Could not prepare the preview. Change a format or try Share again."
                }
            }
            .onDisappear { model.cancel(); model.player?.pause() }
        }
    }

    private var actions: some View {
        VStack(spacing: Spacing.sm) {
            if let error = model.error ?? previewError {
                Text(error).font(AppFont.subheadline).accessibilityIdentifier("workout-share-error")
            }
            if model.photoPermissionDenied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }.minimumHitArea()
            }
            if let notice = model.notice { Text(notice).foregroundStyle(AppColor.recapSuccess) }
            if model.busy {
                ProgressView(value: options.format.isVideo && !model.savingToPhotos ? model.progress : nil)
                Text(model.savingToPhotos ? "Saving to Photos…" : "Preparing share file…").font(AppFont.subheadline)
                if !model.savingToPhotos { Button("Cancel export") { model.cancel() }.minimumHitArea() }
            } else {
                RecapAction(title: "Share") { perform(.share) }
                    .accessibilityIdentifier("workout-share-send")
                Button(options.format.isVideo ? "Save video to Photos" : "Save image to Photos") { perform(.save) }
                    .minimumHitArea().accessibilityIdentifier("workout-share-save")
                if options.format.isVideo {
                    Button("Preview video") { perform(.preview) }.minimumHitArea()
                        .accessibilityIdentifier("workout-share-preview-video")
                }
            }
        }
        .font(AppFont.subheadline)
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.sm)
        .background(AppColor.recapBackground)
    }

    private var previewAccessibilityLabel: String {
        let sets = summary.session.exercises.isEmpty
            ? String(localized: "Sets not logged")
            : summary.workingSetCount == 1
                ? String(localized: "1 working set")
                : String(localized: "\(summary.workingSetCount) working sets")
        return String(localized: "Workout card preview. \(sets). Duration \(summary.duration.label).")
    }

    private var preview: some View {
        ZStack {
            if options.format.isVideo, let player = model.player {
                VideoPlayer(player: player)
                    .accessibilityIdentifier("workout-share-video-player")
            } else if let previewImage {
                Image(uiImage: previewImage).resizable().scaledToFit()
                    .id(previewKey)
                    .transition(.opacity)
                    .accessibilityLabel(previewAccessibilityLabel)
                    .accessibilityIdentifier("workout-share-rendered-\(options.style.rawValue)-\(options.format.rawValue)")
            } else {
                AppColor.recapCard
                if previewError == nil { ProgressView("Preparing preview…") }
            }
        }
        .aspectRatio(options.format.logicalSize.width / options.format.logicalSize.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius))
        // `.contain` keeps the rendered card's and video player's own
        // identifiers; without it this one overrides both.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout-share-preview")
    }

    private func perform(_ action: WorkoutShareController.Action) {
        model.perform(action, summary: summary, unit: unit, options: options, reduceMotion: reduceMotion)
    }
}
