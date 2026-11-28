import WidgetKit
import SwiftUI

// MARK: - Widget Bundle

/// Gallery order is fitness-first: training and nutrition lead, the
/// protocol widgets follow for the people who track one.
@main
struct PeptideWidgetBundle: WidgetBundle {
    var body: some Widget {
        TrainingWidget()
        NutritionWidget()
        FastingWidget()
        NextDoseWidget()
        ComplianceWidget()
        // Nested: a bundle builder takes at most ten widgets directly.
        LiveActivityBundle().body
        ScanMealControl()
        LogWaterControl()
        StartWorkoutControl()
        LogWeightControl()
    }
}

/// The Live Activities, folded into the main bundle through `body`.
struct LiveActivityBundle: WidgetBundle {
    var body: some Widget {
        DoseWindowLiveActivity()
        WorkoutLiveActivity()
        FastingLiveActivity()
    }
}
