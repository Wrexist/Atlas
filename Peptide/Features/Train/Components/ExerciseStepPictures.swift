import SwiftUI

/// An exercise's reviewed steps as numbered pictures side by side: start,
/// peak, and sometimes the middle, cut from its clip. With cues, each
/// picture carries its title and form cue underneath; compact (the workout
/// screen) shows only the numbers. Until the pictures are cut, placeholders
/// hold their 4:5 footprint.
struct ExerciseStepPictures: View {
    let guide: ExerciseStepGuide.Guide
    let images: [CGImage]?
    var showsCues = true

    @ScaledMetric(relativeTo: .headline) private var numberWidth: CGFloat = 24

    var body: some View {
        HStack(alignment: .top, spacing: showsCues ? Spacing.md : Spacing.sm) {
            ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    picture(images.flatMap { index < $0.count ? $0[index] : nil }, number: index + 1)
                    if showsCues {
                        caption(step, number: index + 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Step \(index + 1): \(step.title). \(step.cue)"))
            }
        }
    }

    private func picture(_ image: CGImage?, number: Int) -> some View {
        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
            .fill(AppColor.track)
            .aspectRatio(4 / 5, contentMode: .fit)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .transition(.opacity)
                } else {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .fill(AppColor.track)
                        .shimmer()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .strokeBorder(AppColor.glassBorder, lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                if !showsCues {
                    numberBadge(number)
                        .padding(Spacing.xs)
                }
            }
            .appAnimation(AppAnimation.fadeIn, value: image != nil)
    }

    private func caption(_ step: ExerciseStepGuide.Step, number: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                numberBadge(number)
                Text(step.title)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(step.cue)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func numberBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(AppFont.chipText)
            .monospacedDigit()
            .foregroundStyle(AppColor.textPrimary)
            .frame(width: numberWidth, height: numberWidth)
            .background(Circle().fill(AppColor.surfaceSecondary))
    }
}
