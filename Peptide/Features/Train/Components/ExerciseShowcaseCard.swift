import AVFoundation
import SwiftUI

/// The top of the exercise page: the rendered animation standing straight
/// on the card (a transparent clip has no video box; an opaque one is shown
/// as a rounded dark panel until the transparent set is published), with a
/// Movement / Muscles switch to the interactive body map. An exercise
/// without a clip (custom, not rendered yet, offline on first view) shows
/// the body map alone and no switch.
struct ExerciseShowcaseCard: View {
    let exercise: Exercise
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clip: ExerciseClipStore.Clip?
    /// The exercise `clip` belongs to, so coming back to the same page keeps
    /// the animation up while the lookup reruns instead of flashing the map.
    @State private var clipExerciseID: String?
    @State private var mode: Mode = .movement
    @State private var paused = false

    enum Mode: Hashable, CaseIterable {
        case movement, muscles
    }

    var body: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                if clip != nil {
                    GlassSegmentedControl(options: Mode.allCases, selected: $mode, label: label)
                }
                if let clip, mode == .movement {
                    movement(clip)
                        .transition(.opacity)
                } else {
                    MuscleActivationMap(exercise: exercise)
                        .transition(.opacity)
                }
            }
        }
        .appAnimation(AppAnimation.fadeIn, value: clip)
        .appAnimation(AppAnimation.quick, value: mode)
        .task(id: exercise.id) {
            if clipExerciseID != exercise.id { clip = nil }
            clipExerciseID = exercise.id
            guard !exercise.isCustom else { return }
            clip = await ExerciseClipStore.shared.clip(for: exercise.id)
        }
    }

    private func label(_ mode: Mode) -> LocalizedStringKey {
        switch mode {
        case .movement: "exercise.showcase.movement"
        case .muscles:  "exercise.showcase.muscles"
        }
    }

    private func movement(_ clip: ExerciseClipStore.Clip) -> some View {
        VStack(spacing: Spacing.md) {
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
            MuscleChips(rows: MuscleInvolvementEngine.rows(for: exercise))
        }
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
private struct LoopingVideo: UIViewRepresentable {
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
