import AVFoundation
import SwiftUI

/// The top of the exercise page: the reviewed step pictures (start, peak),
/// each with its cue, and the looping clip one tap away, with a Movement /
/// Muscles switch to the interactive body map. While the clip downloads,
/// placeholders hold the pictures' place, so the page doesn't read as "no
/// animation" and then jump. An exercise without a reviewed guide (custom,
/// not rendered, or its clip failed review) shows the body map alone and no
/// switch.
struct ExerciseShowcaseCard: View {
    let exercise: Exercise
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @State private var clip: ExerciseClipStore.Clip?
    /// The exercise `clip` belongs to, so coming back to the same page keeps
    /// the pictures up while the lookup reruns instead of flashing the map.
    @State private var clipExerciseID: String?
    /// The index lists a clip for this exercise; true before the video is in.
    @State private var hasClip = false
    @State private var images: [CGImage]?
    @State private var mode: Mode = .movement
    @State private var showsVideo = false
    @State private var paused = false

    enum Mode: Hashable, CaseIterable {
        case movement, muscles
    }

    private var guide: ExerciseStepGuide.Guide? {
        ExerciseStepGuide.guide(for: exercise.id, locale: locale)
    }

    var body: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                if hasClip {
                    GlassSegmentedControl(options: Mode.allCases, selected: $mode, label: label)
                }
                if let guide, hasClip, mode == .movement {
                    movement(guide)
                        .transition(.opacity)
                } else {
                    MuscleActivationMap(exercise: exercise)
                        .transition(.opacity)
                }
            }
        }
        .appAnimation(AppAnimation.fadeIn, value: hasClip)
        .appAnimation(AppAnimation.quick, value: mode)
        .appAnimation(AppAnimation.quick, value: showsVideo)
        .task(id: exercise.id) {
            if clipExerciseID != exercise.id {
                clip = nil
                images = nil
                hasClip = false
                showsVideo = false
            }
            clipExerciseID = exercise.id
            guard !exercise.isCustom, let guide else { return }
            let store = ExerciseClipStore.shared
            // A cancelled lookup (page left, exercise changed) writes nothing:
            // the store's index load outlives it and would answer for the
            // old exercise.
            let listed = await store.hasClip(for: exercise.id)
            guard !Task.isCancelled else { return }
            hasClip = listed
            guard listed else {
                clip = nil
                return
            }
            let found = await store.clip(for: exercise.id)
            guard !Task.isCancelled else { return }
            guard let found else {
                // The download failed: fall back to the body map, no dead switch.
                hasClip = false
                return
            }
            clip = found
            let cut = await ExerciseStepImageStore.shared.images(from: found.url, guide: guide)
            guard !Task.isCancelled else { return }
            images = cut
            if cut == nil { hasClip = false }
        }
    }

    private func label(_ mode: Mode) -> LocalizedStringKey {
        switch mode {
        case .movement: "exercise.showcase.movement"
        case .muscles:  "exercise.showcase.muscles"
        }
    }

    private func movement(_ guide: ExerciseStepGuide.Guide) -> some View {
        VStack(spacing: Spacing.md) {
            if showsVideo, let clip {
                video(clip)
                    .transition(.opacity)
            } else {
                Button { showsVideo = true } label: {
                    ExerciseStepPictures(guide: guide, images: images)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ScalePressStyle())
                .disabled(clip == nil)
                .accessibilityHint(Text("Plays the movement as a video"))
                .transition(.opacity)
            }
            toggleButton
            MuscleChips(rows: MuscleInvolvementEngine.rows(for: exercise))
        }
    }

    private func video(_ clip: ExerciseClipStore.Clip) -> some View {
        LoopingVideo(url: clip.url, isTransparent: clip.isTransparent, playing: !reduceMotion && !paused)
            .id(clip.url)
            .aspectRatio(4 / 5, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: clip.isTransparent ? 0 : Spacing.controlCornerRadius, style: .continuous))
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottomTrailing) {
                if !reduceMotion { pauseButton }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Animation of \(exercise.name)"))
    }

    /// Steps first; the video is one tap away and back.
    private var toggleButton: some View {
        Button {
            showsVideo.toggle()
        } label: {
            Label(showsVideo ? "Show steps" : "Play video", systemImage: showsVideo ? "square.grid.2x2" : "play.fill")
                .font(AppFont.chipText)
                .foregroundStyle(AppColor.textPrimary)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: Spacing.minimumHitTarget)
                .glassControl(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(clip == nil)
        .opacity(clip == nil ? 0.5 : 1)
    }

    private var pauseButton: some View {
        Button {
            paused.toggle()
        } label: {
            Image(systemName: paused ? "play.fill" : "pause.fill")
                .font(AppFont.chipText)
                .foregroundStyle(AppColor.textPrimary)
                .frame(width: Spacing.minimumHitTarget, height: Spacing.minimumHitTarget)
                .glassControl(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(paused ? Text("Play animation") : Text("Pause animation"))
    }
}

/// The worked muscles under the animation, one chip each, with the same
/// colour dot the figure is tinted with: prime movers first.
private struct MuscleChips: View {
    let rows: [MuscleInvolvementEngine.Row]

    var body: some View {
        if !rows.isEmpty {
            FlowLayout(spacing: Spacing.xs) {
                ForEach(rows) { row in
                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(row.role == .primary ? AppColor.trainingPrimaryMuscle : AppColor.trainingSecondaryMuscle)
                            .frame(width: Spacing.sm, height: Spacing.sm)
                        Text(row.name)
                            .font(AppFont.chipText)
                            .foregroundStyle(AppColor.textPrimary)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Capsule().fill(AppColor.surfaceSecondary.opacity(0.6)))
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(Text(row.role.displayName))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// AVPlayerLayer without playback controls, looping a short local clip.
/// A transparent clip is HEVC with alpha: the layer asks for BGRA frames and
/// has no background of its own, so the card shows through around the
/// figure. An opaque clip keeps the cheaper native frame format.
struct LoopingVideo: UIViewRepresentable {
    let url: URL
    let isTransparent: Bool
    let playing: Bool

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        if isTransparent {
            view.playerLayer.pixelBufferAttributes = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        }
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        if playing { view.playerLayer.player?.play() } else { view.playerLayer.player?.pause() }
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: Coordinator) {
        view.playerLayer.player?.pause()
        coordinator.looper = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var looper: AVPlayerLooper?
    }

    final class PlayerView: UIView {
        let playerLayer = AVPlayerLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isOpaque = false
            backgroundColor = .clear
            playerLayer.backgroundColor = UIColor.clear.cgColor
            layer.addSublayer(playerLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }
    }
}
