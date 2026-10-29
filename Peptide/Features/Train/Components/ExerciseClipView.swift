import AVFoundation
import SwiftUI

/// The exercise's rendered animation, looping silently above the body map.
/// Takes no space until the clip is on the device, so an exercise without
/// one (or a phone offline on first view) shows the body map alone.
/// The wrapper is a ZStack, not a Group: a Group passes its modifiers to its
/// children, and with no clip yet there is no child, so `.task` never ran.
struct ExerciseClipView: View {
    let exercise: Exercise
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clipURL: URL?

    var body: some View {
        ZStack {
            if let clipURL {
                LoopingVideo(url: clipURL, playing: !reduceMotion)
                    .aspectRatio(4 / 5, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous))
                    .transition(.opacity)
                    .accessibilityElement()
                    .accessibilityLabel(Text("Animation of \(exercise.name)"))
            }
        }
        .appAnimation(AppAnimation.fadeIn, value: clipURL)
        .task(id: exercise.id) {
            guard !exercise.isCustom else { return }
            clipURL = await ExerciseClipStore.shared.clip(for: exercise.id)
        }
    }
}

/// AVPlayerLayer without playback controls, looping a short local clip.
private struct LoopingVideo: UIViewRepresentable {
    let url: URL
    let playing: Bool

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
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
