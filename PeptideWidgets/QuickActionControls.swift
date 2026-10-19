import AppIntents
import SwiftUI
import WidgetKit

/// Control Center, Lock Screen and Action button controls — one per
/// `QuickAction`. Water logs in place without opening Atlas; the rest
/// open the app straight into the scanner, a workout or weight entry.
struct LogWaterControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.peptidesai.app.control.logWater") {
            ControlWidgetButton(action: LogWaterGlassIntent()) {
                Label {
                    Text(QuickAction.logWater.title)
                } icon: {
                    Image(systemName: QuickAction.logWater.systemImage)
                }
            }
        }
        .displayName("Log water")
        .description("Adds a glass of water to today without opening Atlas.")
    }
}

struct ScanMealControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        QuickActionControlConfiguration.make(.scanMeal, description: "Opens the meal scanner.")
    }
}

struct StartWorkoutControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        QuickActionControlConfiguration.make(.startWorkout, description: "Starts a workout in Atlas.")
    }
}

struct LogWeightControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        QuickActionControlConfiguration.make(.logWeight, description: "Opens weight entry in Atlas.")
    }
}

private enum QuickActionControlConfiguration {
    static func make(_ action: QuickAction, description: LocalizedStringResource) -> some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.peptidesai.app.control.\(action.rawValue)") {
            ControlWidgetButton(action: OpenQuickActionIntent(action: action)) {
                Label {
                    Text(action.title)
                } icon: {
                    Image(systemName: action.systemImage)
                }
            }
        }
        .displayName(action.title)
        .description(description)
    }
}
