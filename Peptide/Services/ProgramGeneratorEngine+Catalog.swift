import Foundation

/// The curated exercise shortlist per movement pattern, and the day
/// templates built from those patterns. Hand-picked rather than queried
/// out of the 873-exercise dataset so a generated program reads like one
/// a coach wrote — Barbell Squat, not "Kneeling Jump Squat".
///
/// Each list is in preference order and deliberately spans equipment:
/// the generator takes the first entry the user can do, so a full gym
/// gets the barbell lift and a hotel room gets the bodyweight one.
/// `ProgramGeneratorEngineTests` asserts every id resolves in
/// `exercises.json`.
extension ProgramGeneratorEngine {

    static func candidates(for pattern: MovementPattern) -> [String] {
        switch pattern {
        case .squat:
            return [
                "Barbell_Squat", "Front_Squat_Clean_Grip", "Hack_Squat", "Leg_Press",
                "Goblet_Squat", "Dumbbell_Squat", "Smith_Machine_Squat",
                "Squats_-_With_Bands", "Bodyweight_Squat",
            ]
        case .hinge:
            return [
                "Romanian_Deadlift", "Barbell_Deadlift", "Barbell_Hip_Thrust", "Trap_Bar_Deadlift",
                "Stiff-Legged_Dumbbell_Deadlift", "One-Arm_Kettlebell_Swings",
                "Kettlebell_One-Legged_Deadlift", "Cable_Deadlifts",
                "Smith_Machine_Stiff-Legged_Deadlift", "Band_Good_Morning",
                "Single_Leg_Glute_Bridge", "Butt_Lift_Bridge",
            ]
        case .lunge:
            return [
                "Dumbbell_Lunges", "Split_Squat_with_Dumbbells", "Barbell_Walking_Lunge",
                "Dumbbell_Step_Ups", "Barbell_Lunge", "Dumbbell_Rear_Lunge",
                "Smith_Single-Leg_Split_Squat", "Lunge_Pass_Through",
                "Bodyweight_Walking_Lunge", "Step-up_with_Knee_Raise",
            ]
        case .horizontalPush:
            return [
                "Barbell_Bench_Press_-_Medium_Grip", "Dumbbell_Bench_Press",
                "Barbell_Incline_Bench_Press_-_Medium_Grip", "Incline_Dumbbell_Press",
                "Machine_Bench_Press", "Leverage_Chest_Press", "Cable_Chest_Press",
                "Alternating_Floor_Press", "Bench_Press_-_With_Bands",
                "Pushups", "Incline_Push-Up", "Push-Up_Wide",
            ]
        case .horizontalPull:
            return [
                "Bent_Over_Barbell_Row", "One-Arm_Dumbbell_Row", "Seated_Cable_Rows",
                "T-Bar_Row_with_Handle", "Bent_Over_Two-Dumbbell_Row", "Leverage_Iso_Row",
                "Two-Arm_Kettlebell_Row", "One-Arm_Kettlebell_Row", "Inverted_Row",
            ]
        case .verticalPush:
            return [
                "Standing_Military_Press", "Seated_Dumbbell_Press", "Dumbbell_Shoulder_Press",
                "Machine_Shoulder_Military_Press", "Leverage_Shoulder_Press",
                "Cable_Shoulder_Press", "Two-Arm_Kettlebell_Military_Press",
                "Shoulder_Press_-_With_Bands", "Push-Ups_With_Feet_Elevated", "Decline_Push-Up",
            ]
        case .verticalPull:
            return [
                "Wide-Grip_Lat_Pulldown", "Pullups", "Close-Grip_Front_Lat_Pulldown",
                "Chin-Up", "Underhand_Cable_Pulldowns", "Straight-Arm_Dumbbell_Pullover",
                "V-Bar_Pullup",
            ]
        case .chestIsolation:
            return [
                "Dumbbell_Flyes", "Butterfly", "Flat_Bench_Cable_Flyes",
                "Incline_Dumbbell_Flyes", "Cross_Over_-_With_Bands",
            ]
        case .lateralDelt:
            return [
                "Side_Lateral_Raise", "Cable_Seated_Lateral_Raise",
                "Seated_Side_Lateral_Raise", "Lateral_Raise_-_With_Bands",
            ]
        case .rearDelt:
            return [
                "Face_Pull", "Reverse_Flyes", "Reverse_Machine_Flyes",
                "Cable_Rear_Delt_Fly", "Band_Pull_Apart",
            ]
        case .biceps:
            return [
                "Barbell_Curl", "Dumbbell_Bicep_Curl", "Hammer_Curls", "EZ-Bar_Curl",
                "Standing_Biceps_Cable_Curl", "Machine_Bicep_Curl", "Incline_Dumbbell_Curl",
            ]
        case .triceps:
            return [
                "Triceps_Pushdown", "EZ-Bar_Skullcrusher", "Standing_Dumbbell_Triceps_Extension",
                "Triceps_Pushdown_-_Rope_Attachment", "Machine_Triceps_Extension",
                "Band_Skull_Crusher", "Tricep_Dumbbell_Kickback",
                "Dips_-_Triceps_Version", "Bench_Dips",
            ]
        case .quadIsolation:
            return ["Leg_Extensions", "Single-Leg_Leg_Extension"]
        case .hamstringIsolation:
            return [
                "Lying_Leg_Curls", "Seated_Leg_Curl", "Standing_Leg_Curl",
                "Ball_Leg_Curl", "Natural_Glute_Ham_Raise",
            ]
        case .calves:
            return [
                "Standing_Calf_Raises", "Seated_Calf_Raise", "Standing_Barbell_Calf_Raise",
                "Dumbbell_Seated_One-Leg_Calf_Raise", "Calf_Raises_-_With_Bands",
            ]
        case .core:
            return [
                "Hanging_Leg_Raise", "Cable_Crunch", "One-Arm_Medicine_Ball_Slam",
                "Exercise_Ball_Crunch", "Dead_Bug", "Reverse_Crunch",
                "Flat_Bench_Lying_Leg_Raise", "Crunches",
            ]
        }
    }

    /// One training day's shape. Patterns run in workout order, which is
    /// also priority order: a short session keeps the front of the list
    /// and loses isolation work from the back. Antagonist isolation
    /// patterns sit next to each other so they can pair into a superset.
    enum DayTemplate: CaseIterable, Sendable {
        case fullBodyA, fullBodyB, fullBodyC
        case upperA, upperB, lowerA, lowerB
        case push, pull, legs

        var title: String {
            switch self {
            case .fullBodyA, .fullBodyB, .fullBodyC: return "Full body"
            case .upperA, .upperB:                   return "Upper"
            case .lowerA, .lowerB:                   return "Lower"
            case .push:                              return "Push"
            case .pull:                              return "Pull"
            case .legs:                              return "Legs"
            }
        }

        var patterns: [MovementPattern] {
            switch self {
            case .fullBodyA:
                return [.squat, .horizontalPush, .horizontalPull, .hinge, .lateralDelt, .triceps, .biceps, .core]
            case .fullBodyB:
                return [.hinge, .verticalPush, .verticalPull, .lunge, .chestIsolation, .rearDelt, .calves, .core]
            case .fullBodyC:
                return [.squat, .horizontalPush, .verticalPull, .lunge, .quadIsolation, .hamstringIsolation, .core]
            case .upperA:
                return [.horizontalPush, .horizontalPull, .verticalPush, .verticalPull, .lateralDelt, .triceps, .biceps]
            case .upperB:
                return [.verticalPush, .verticalPull, .horizontalPush, .horizontalPull, .chestIsolation, .rearDelt, .biceps, .triceps]
            case .lowerA:
                return [.squat, .hinge, .lunge, .quadIsolation, .hamstringIsolation, .calves, .core]
            case .lowerB:
                return [.hinge, .squat, .lunge, .hamstringIsolation, .quadIsolation, .calves, .core]
            case .push:
                return [.horizontalPush, .verticalPush, .horizontalPush, .chestIsolation, .lateralDelt, .triceps]
            case .pull:
                return [.verticalPull, .horizontalPull, .verticalPull, .rearDelt, .biceps, .core]
            case .legs:
                return [.squat, .hinge, .lunge, .quadIsolation, .hamstringIsolation, .calves, .core]
            }
        }
    }

    /// The week for a day count. Five days is push/pull/legs plus an
    /// upper and a lower day, so legs still get trained twice.
    static func week(forDays days: Int) -> [DayTemplate] {
        switch days {
        case ...2: return [.fullBodyA, .fullBodyB]
        case 3:    return [.fullBodyA, .fullBodyB, .fullBodyC]
        case 4:    return [.upperA, .lowerA, .upperB, .lowerB]
        case 5:    return [.push, .pull, .legs, .upperA, .lowerA]
        default:   return [.push, .pull, .legs, .push, .pull, .legs]
        }
    }

    /// Full-body days in rotation — the fallback for a week whose split
    /// needs kit the user doesn't have.
    static func fullBodyWeek(days: Int) -> [DayTemplate] {
        let rotation: [DayTemplate] = [.fullBodyA, .fullBodyB, .fullBodyC]
        return (0..<days).map { rotation[$0 % rotation.count] }
    }
}
