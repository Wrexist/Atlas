import Foundation

/// Works out what kit an exercise uses from the dataset's raw equipment
/// string and the exercise's name. The raw string alone is coarse and
/// sometimes wrong: every Smith machine lift is tagged "machine", the trap
/// bar deadlift and most pull-ups are "other", and stretches with no kit at
/// all are "other" too. Name keywords fix the systematic cases; `overrides`
/// holds the handful keywords can't reach.
enum EquipmentClassificationEngine {

    static func kind(for exercise: Exercise) -> EquipmentKind {
        kind(id: exercise.id, name: exercise.name, raw: exercise.equipment, category: exercise.category)
    }

    static func accessories(for exercise: Exercise) -> Set<EquipmentAccessory> {
        accessories(id: exercise.id, name: exercise.name, kind: kind(for: exercise), category: exercise.category)
    }

    // MARK: - Kind

    static func kind(id: String, name: String, raw: String?, category: Exercise.Category) -> EquipmentKind {
        if let override = kindOverrides[id] { return override }
        let base = EquipmentKind.fromRaw(raw)
        let lowered = name.lowercased()

        if lowered.contains("smith") { return .smith }
        if lowered.containsAny("trap bar", "hex bar") { return .trapBar }
        if base == .barbell || base == .other, lowered.containsAny("ez bar", "ez-bar", "e-z bar", "ez curl") {
            return .ezBar
        }
        guard base == .other || base == .bodyweight else { return base }
        return looseKind(name: lowered, base: base, category: category)
    }

    /// Kind for an exercise the dataset left as "other" or untagged: the
    /// name names the kit, or the movement is plainly bodyweight.
    private static func looseKind(name: String, base: EquipmentKind, category: Exercise.Category) -> EquipmentKind {
        if name.contains("medicine ball") { return .medicineBall }
        if name.containsAny("stability ball", "exercise ball", "swiss ball", "physioball") { return .swissBall }
        if name.hasSuffix("-smr") || name.contains("foam roll") { return .foamRoller }
        guard base == .other else { return base }
        if name.contains("plate") { return .plate }
        if category == .stretching || category == .plyometrics { return .bodyweight }
        if name.containsAny(bodyweightKeywords) { return .bodyweight }
        return .other
    }

    /// Hanging and dipping work the dataset tags "other" because it
    /// needs a bar — the load is still the body.
    private static let bodyweightKeywords = ["pull-up", "pull up", "pullup", "chin", "dip", "muscle up"]

    /// Exercises the keyword rules get wrong, by dataset id.
    static let kindOverrides: [String: EquipmentKind] = [
        "Axle_Deadlift": .barbell,
        "Band_Assisted_Pull-Up": .band,
        "Seated_Band_Hamstring_Curl": .band,
        "Weighted_Sit-Ups_-_With_Bands": .band,
        "Bodyweight_Mid_Row": .bodyweight,
        "Platform_Hamstring_Slides": .bodyweight,
        "Kipping_Muscle_Up": .bodyweight,
        "Knee_Hip_Raise_On_Parallel_Bars": .bodyweight,
        "Single-Leg_High_Box_Squat": .bodyweight,
        "Otis-Up": .plate,
        "Svend_Press": .plate,
        "Weighted_Bench_Dip": .plate,
        "Donkey_Calf_Raises": .machine,
        "Hyperextensions_Back_Extensions": .machine,
        // Chain loads on cable handles, rings and slings: no kind fits.
        "Chain_Press": .other,
        "Chain_Handle_Extension": .other,
        "Ring_Dips": .other,
        "Inverted_Row_with_Straps": .other,
        "Heavy_Bag_Thrust": .other,
        "Sledgehammer_Swings": .other,
    ]

    // MARK: - Accessories

    static func accessories(
        id: String, name: String, kind: EquipmentKind, category: Exercise.Category
    ) -> Set<EquipmentAccessory> {
        let lowered = name.lowercased()
        var needs = accessoryOverrides[id] ?? []
        if needsBench(name: lowered, kind: kind, category: category) { needs.insert(.bench) }
        if needsRack(name: lowered, kind: kind) { needs.insert(.rack) }
        if needsPullUpBar(name: lowered, kind: kind, category: category) { needs.insert(.pullUpBar) }
        if needsBox(name: lowered) { needs.insert(.box) }
        return needs
    }

    private static func needsBench(name: String, kind: EquipmentKind, category: Exercise.Category) -> Bool {
        guard kind != .machine, category != .cardio else { return false }
        if name.contains("bench") { return !name.contains("no hyperextension bench") }
        if name.containsAny("incline", "decline", "skullcrusher", "skull crusher", "preacher") { return true }
        let freeWeight: Set<EquipmentKind> = [.barbell, .dumbbell, .ezBar]
        guard freeWeight.contains(kind) else { return false }
        if name.hasPrefix("seated") { return true }
        if kind == .dumbbell, name.containsAny("flye", "flyes", "fly "), !name.containsAny("bent over", "standing") {
            return true
        }
        return name.contains("lying") && name.containsAny("triceps", "extension", "press", "row")
    }

    private static func needsRack(name: String, kind: EquipmentKind) -> Bool {
        guard kind == .barbell else { return false }
        return name.containsAny(
            "squat", "bench press", "rack", "good morning", "lunge", "military press",
            "shoulder press", "overhead press", "push press", "jerk", "floor press"
        )
    }

    private static func needsPullUpBar(name: String, kind: EquipmentKind, category: Exercise.Category) -> Bool {
        guard kind == .bodyweight || kind == .band else { return false }
        if name.containsAny("pull-up", "pull up", "pullup", "chin-up", "chinup", "muscle up", "muscle-up") { return true }
        if category != .stretching, name.contains("chin") { return true }
        return name.hasPrefix("hanging") || (kind == .bodyweight && name.contains("hang"))
    }

    private static func needsBox(name: String) -> Bool {
        name.containsAny("box ", "depth jump", "step-up", "step up") || name.hasSuffix(" box")
    }

    /// Needs the name doesn't mention, by dataset id.
    static let accessoryOverrides: [String: Set<EquipmentAccessory>] = [
        "Inverted_Row": [.rack],
        "Bodyweight_Mid_Row": [.pullUpBar],
        "Chain_Press": [.bench],
        "Chain_Handle_Extension": [.bench],
    ]
}

private extension String {
    func containsAny(_ needles: String...) -> Bool {
        containsAny(needles)
    }

    func containsAny(_ needles: [String]) -> Bool {
        needles.contains { contains($0) }
    }
}
