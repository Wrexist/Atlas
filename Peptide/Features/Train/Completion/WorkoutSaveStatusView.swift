import SwiftUI

struct WorkoutSaveStatusView: View {
    let saving: Bool
    let error: String?
    let retry: () -> Void
    let returnToWorkout: () -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                if saving {
                    ProgressView().controlSize(.large).tint(AppColor.recapAction)
                    Text("Saving workout…").font(AppFont.title2)
                } else {
                    Image(systemName: "exclamationmark.circle").font(AppFont.scaled(52, weight: .regular))
                        .foregroundStyle(AppColor.destructive).accessibilityHidden(true)
                    Text("Couldn’t save workout").font(AppFont.title2)
                    Text(error ?? "Please try again.").font(AppFont.body)
                    Text("Return to the workout to review your sets.").font(AppFont.subheadline)
                    RecapAction(title: "Retry", action: retry)
                    Button("Return to workout", action: returnToWorkout).frame(minHeight: 44)
                }
            }.multilineTextAlignment(.center).padding(Spacing.screenPadding).padding(.top, Spacing.xxxxl)
        }.recapScreen(title: saving ? "Saving" : "Save error")
    }
}
