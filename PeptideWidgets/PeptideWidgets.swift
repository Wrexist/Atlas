import WidgetKit
import SwiftUI

/// Deep-link targets for widget taps, routed by the app's
/// `DeepLinkRouter`. Before these, every home-screen widget tap just
/// foregrounded the app on whatever tab was last open — a nutrition
/// widget tap could land on Biology. `widgetURL` needs no
/// CFBundleURLTypes registration for same-app links, but the scheme
/// is registered anyway so notification and Shortcuts links resolve.
enum WidgetDeepLink {
    static let today = URL(string: "peptidex://today")
    static let meals = URL(string: "peptidex://meals")
    static let train = URL(string: "peptidex://train")
}

// MARK: - Widget Bundle

/// Gallery order is fitness-first: training and nutrition lead, the
/// protocol widgets follow for the people who track one.
@main
struct PeptideWidgetBundle: WidgetBundle {
    var body: some Widget {
        TrainingWidget()
        NutritionWidget()
        NextDoseWidget()
        ComplianceWidget()
        DoseWindowLiveActivity()
        WorkoutLiveActivity()
        ScanMealControl()
        LogWaterControl()
        StartWorkoutControl()
        LogWeightControl()
    }
}
