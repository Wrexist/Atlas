import Foundation

/// Where a session happens. Each place keeps its own equipment profile,
/// so switching from the gym to home swaps the kit the session builder
/// may use without re-ticking anything.
enum TrainingLocation: String, CaseIterable, Codable, Identifiable, Sendable {
    case gym
    case home

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gym: String(localized: "location.gym", defaultValue: "Gym")
        case .home: String(localized: "location.home", defaultValue: "Home")
        }
    }

    var symbol: String {
        switch self {
        case .gym: "building.2"
        case .home: "house"
        }
    }
}

/// A specific machine on the gym floor. The dataset tags all of them
/// "machine"; a home gym or a small studio has some and not others, so
/// the builder asks per machine rather than for "machines" as a whole.
enum GymMachine: String, CaseIterable, Codable, Identifiable, Sendable {
    case legPress, hackSquat, legExtension, legCurl, calfRaise
    case chestPress, shoulderPress, seatedRow, pecDeck, armMachine
    case hipMachine, abMachine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .legPress: String(localized: "machine.legPress", defaultValue: "Leg press")
        case .hackSquat: String(localized: "machine.hackSquat", defaultValue: "Hack squat")
        case .legExtension: String(localized: "machine.legExtension", defaultValue: "Leg extension")
        case .legCurl: String(localized: "machine.legCurl", defaultValue: "Leg curl")
        case .calfRaise: String(localized: "machine.calfRaise", defaultValue: "Calf raise")
        case .chestPress: String(localized: "machine.chestPress", defaultValue: "Chest press")
        case .shoulderPress: String(localized: "machine.shoulderPress", defaultValue: "Shoulder press")
        case .seatedRow: String(localized: "machine.seatedRow", defaultValue: "Row machine")
        case .pecDeck: String(localized: "machine.pecDeck", defaultValue: "Pec deck")
        case .armMachine: String(localized: "machine.armMachine", defaultValue: "Arm curl / extension")
        case .hipMachine: String(localized: "machine.hipMachine", defaultValue: "Hip abduction / adduction")
        case .abMachine: String(localized: "machine.abMachine", defaultValue: "Ab crunch")
        }
    }

    /// The machine a "machine" exercise is done on. Nil for the few that
    /// don't name one (cardio kit, glute-ham bench): those count as
    /// available whenever any machine is.
    static func required(for exerciseID: String) -> GymMachine? {
        byExercise[exerciseID]
    }

    private static let byExercise: [String: GymMachine] = [
        "Leg_Press": .legPress, "Narrow_Stance_Leg_Press": .legPress,
        "Calf_Press_On_The_Leg_Press_Machine": .legPress,
        "Hack_Squat": .hackSquat, "Narrow_Stance_Hack_Squats": .hackSquat, "Lying_Machine_Squat": .hackSquat,
        "Leg_Extensions": .legExtension, "Single-Leg_Leg_Extension": .legExtension,
        "Lying_Leg_Curls": .legCurl, "Seated_Leg_Curl": .legCurl, "Standing_Leg_Curl": .legCurl,
        "Standing_Calf_Raises": .calfRaise, "Seated_Calf_Raise": .calfRaise, "Calf_Press": .calfRaise,
        "Calf-Machine_Shoulder_Shrug": .calfRaise,
        "Machine_Bench_Press": .chestPress, "Leverage_Chest_Press": .chestPress,
        "Leverage_Decline_Chest_Press": .chestPress, "Leverage_Incline_Chest_Press": .chestPress,
        "Machine_Shoulder_Military_Press": .shoulderPress, "Leverage_Shoulder_Press": .shoulderPress,
        "Leverage_Iso_Row": .seatedRow, "Leverage_High_Row": .seatedRow, "Lying_T-Bar_Row": .seatedRow,
        "Butterfly": .pecDeck, "Reverse_Machine_Flyes": .pecDeck,
        "Machine_Bicep_Curl": .armMachine, "Machine_Preacher_Curls": .armMachine,
        "Machine_Triceps_Extension": .armMachine, "Dip_Machine": .armMachine,
        "Thigh_Abductor": .hipMachine, "Thigh_Adductor": .hipMachine,
        "Ab_Crunch_Machine": .abMachine,
    ]
}

/// The kit one training place has: free weights and stations as
/// `EquipmentKind`s, the bench / rack / bar / box as accessories, and the
/// machines one by one. The session builder only picks exercises this
/// profile allows.
struct EquipmentProfile: Codable, Hashable, Sendable {
    var kinds: Set<EquipmentKind>
    var accessories: Set<EquipmentAccessory>
    var machines: Set<GymMachine>

    /// Kinds the profile editor offers. Machines are asked one by one, and
    /// bodyweight is always there.
    static let kindChoices: [EquipmentKind] = EquipmentKind.accessChoices
        .filter { $0 != .machine && $0 != .bodyweight && $0 != .foamRoller }

    static func standard(for location: TrainingLocation) -> EquipmentProfile {
        switch location {
        case .gym:
            EquipmentProfile(kinds: Set(kindChoices), accessories: Set(EquipmentAccessory.allCases),
                             machines: Set(GymMachine.allCases))
        case .home:
            EquipmentProfile(kinds: [.dumbbell, .band], accessories: [], machines: [])
        }
    }

    /// A profile from a plain access set, the way onboarding stores it:
    /// every kind that set vouches for, the accessories it implies, and
    /// every machine when it includes machines.
    init(access: Set<EquipmentKind>) {
        kinds = Set(EquipmentKind.allCases.filter { $0.isAvailable(with: access) })
        accessories = EquipmentAccessory.implied(by: access)
        machines = access.contains(.machine) ? Set(GymMachine.allCases) : []
    }

    init(kinds: Set<EquipmentKind>, accessories: Set<EquipmentAccessory>, machines: Set<GymMachine>) {
        self.kinds = kinds
        self.accessories = accessories
        self.machines = machines
    }

    /// Everything ticked, bodyweight not counted.
    var itemCount: Int { kinds.count + accessories.count + machines.count }

    func allows(_ exercise: Exercise) -> Bool {
        guard exercise.equipmentAccessories.isSubset(of: accessories) else { return false }
        let kind = exercise.equipmentKind
        switch kind {
        case .bodyweight:
            return true
        case .machine:
            return GymMachine.required(for: exercise.id).map(machines.contains) ?? !machines.isEmpty
        case .plate:
            return !kinds.isDisjoint(with: [.barbell, .smith, .ezBar, .trapBar])
        default:
            return kinds.contains(kind)
        }
    }
}
