import SwiftUI

/// `MuscleMapView` that ignites on appear: a soft scan sweeps the figure,
/// prime movers light, then supporting muscles fill in. After the reveal it
/// tracks `highlights` live, so a caller can refocus it. Reduce Motion
/// shows the final state at once.
struct StagedMuscleMap: View {
    let highlights: [AnatomicalMuscle: MuscleHighlight]
    var primaryColor: Color = AppColor.trainingPrimaryMuscle
    var secondaryColor: Color = AppColor.trainingSecondaryMuscle
    var identifiesOnTap: Bool = true
    var onIdentify: ((AnatomicalMuscle) -> Void)? = nil
    var selectedMuscle: AnatomicalMuscle? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = 0
    @State private var scanProgress: CGFloat = 0
    @State private var scanVisible = false

    private var stages: [[AnatomicalMuscle: MuscleHighlight]] {
        MuscleInvolvementEngine.revealStages(for: highlights)
    }

    private var shown: [AnatomicalMuscle: MuscleHighlight] {
        revealed >= stages.count ? highlights : (revealed == 0 ? [:] : stages[revealed - 1])
    }

    var body: some View {
        MuscleMapView(
            highlights: shown,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
            identifiesOnTap: identifiesOnTap,
            onIdentify: onIdentify,
            selectedMuscle: revealed >= stages.count ? selectedMuscle : nil
        )
        .overlay { scanBeam }
        .task { await reveal() }
    }

    private var scanBeam: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, primaryColor.opacity(0.28), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: geo.size.height * 0.18)
            .offset(y: scanProgress * geo.size.height * 1.18 - geo.size.height * 0.18)
            .blendMode(.plusLighter)
            .opacity(scanVisible ? 1 : 0)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func reveal() async {
        guard revealed == 0 else { return }
        if reduceMotion {
            revealed = stages.count
            return
        }
        scanVisible = true
        withAnimation(AppAnimation.muscleScan) { scanProgress = 1 }
        for stage in 1...stages.count {
            try? await Task.sleep(for: AppAnimation.muscleStageDelay)
            guard !Task.isCancelled else { return }
            withAnimation(AppAnimation.springSmooth) { revealed = stage }
        }
        withAnimation(AppAnimation.fadeInSlow) { scanVisible = false }
    }
}

extension AppAnimation {
    /// Gap between muscle-map ignite stages (prime movers, then supporting).
    static let muscleStageDelay: Duration = .milliseconds(320)
}

#Preview {
    StagedMuscleMap(highlights: [.pecSternal: .primary, .pecClavicular: .primary,
                                 .deltAnterior: .secondary, .tricepsLateral: .secondary])
        .padding()
        .background(AppColor.background)
        .preferredColorScheme(.dark)
}
