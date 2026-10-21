import Foundation

/// Equipment taxonomy used by the Train tab filter row, the exercise tile
/// badge, progression increments, the plate calculator and onboarding's
/// "equipment access" multi-select.
///
/// Raw values are persisted (`TrainingPreferences.equipmentAccess`, custom
/// exercises' `equipment` string), so a case's raw value never changes;
/// `allCases` order is only display order. A bundled exercise's kind comes from
/// `EquipmentClassificationEngine`, which reads the dataset's raw string
/// and the exercise name together — the dataset tags Smith machine work as
/// "machine" and pull-ups as "other", so the raw string alone is wrong.
enum EquipmentKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case barbell
    case dumbbell
    case kettlebell
    case cable
    case machine
    case smith
    case ezBar
    case trapBar
    case band
    case plate
    case medicineBall
    case swissBall
    case foamRoller
    case bodyweight
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .barbell:      return "Barbell"
        case .dumbbell:     return "Dumbbell"
        case .kettlebell:   return "Kettlebell"
        case .cable:        return "Cable"
        case .machine:      return "Machine"
        case .smith:        return "Smith machine"
        case .ezBar:        return "EZ bar"
        case .trapBar:      return "Trap bar"
        case .band:         return "Bands"
        case .plate:        return "Weight plate"
        case .medicineBall: return "Medicine ball"
        case .swissBall:    return "Swiss ball"
        case .foamRoller:   return "Foam roller"
        case .bodyweight:   return "Bodyweight"
        case .other:        return "Other"
        }
    }

    /// SF Symbols where one reads as the kit; the rest are the custom
    /// template glyphs in `Assets.xcassets/Equipment`.
    var glyph: AppGlyph {
        switch self {
        case .barbell:      return .asset("equipment-barbell")
        case .dumbbell:     return .system("dumbbell.fill")
        case .kettlebell:   return .asset("equipment-kettlebell")
        case .cable:        return .asset("equipment-cable")
        case .machine:      return .asset("equipment-machine")
        case .smith:        return .asset("equipment-smith")
        case .ezBar:        return .asset("equipment-ezbar")
        case .trapBar:      return .asset("equipment-trapbar")
        case .band:         return .asset("equipment-band")
        case .plate:        return .asset("equipment-plate")
        case .medicineBall: return .asset("equipment-medicineball")
        case .swissBall:    return .asset("equipment-swissball")
        case .foamRoller:   return .asset("equipment-foamroller")
        case .bodyweight:   return .system("figure.core.training")
        case .other:        return .system("ellipsis.circle")
        }
    }

    /// The bar a plate-loaded kind is loaded on; nil for everything the
    /// plate calculator doesn't apply to.
    var bar: BarKind? {
        switch self {
        case .barbell: return .olympic
        case .smith:   return .smith
        case .ezBar:   return .ezBar
        case .trapBar: return .trapBar
        default:       return nil
        }
    }

    /// Kinds offered in onboarding's equipment grid. `.plate` comes with
    /// any bar and `.other` is a catch-all, so neither is a choice.
    static let accessChoices: [EquipmentKind] = allCases.filter { $0 != .plate && $0 != .other }

    /// True when a user with `access` can do an exercise of this kind.
    /// A barbell gym has an EZ bar and plates, and a machine gym has a
    /// Smith machine — which is also how these exercises were classified
    /// before they had kinds of their own, so saved access sets keep
    /// matching the same exercises.
    func isAvailable(with access: Set<EquipmentKind>) -> Bool {
        if access.contains(self) { return true }
        switch self {
        case .ezBar: return access.contains(.barbell)
        case .smith: return access.contains(.machine)
        case .plate: return !access.isDisjoint(with: [.barbell, .smith, .ezBar, .trapBar])
        default:     return false
        }
    }

    /// Maps a raw equipment string — the dataset's vocabulary or a custom
    /// exercise's stored `rawValue` — to a kind, without looking at the
    /// exercise name. Missing / "none" reads as bodyweight; anything
    /// unrecognised is `.other`.
    static func fromRaw(_ raw: String?) -> EquipmentKind {
        guard let raw = raw?.lowercased(), !raw.isEmpty else { return .bodyweight }
        switch raw {
        case "barbell":                                 return .barbell
        case "dumbbell":                                return .dumbbell
        case "kettlebells", "kettlebell":               return .kettlebell
        case "cable":                                   return .cable
        case "machine":                                 return .machine
        case "smith machine", "smith":                  return .smith
        case "e-z curl bar", "ezbar":                   return .ezBar
        case "trap bar", "trapbar":                     return .trapBar
        case "bands", "band":                           return .band
        case "plate":                                   return .plate
        case "medicine ball", "medicineball":           return .medicineBall
        case "exercise ball", "swissball":              return .swissBall
        case "foam roll", "foamroller":                 return .foamRoller
        case "body only", "bodyweight", "none":         return .bodyweight
        default:                                        return .other
        }
    }
}

/// Kit an exercise needs besides its main equipment — a bench to press
/// on, a rack to unrack from, a bar to hang from, a box to jump onto.
enum EquipmentAccessory: String, CaseIterable, Codable, Identifiable, Sendable {
    case bench
    case rack
    case pullUpBar
    case box

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bench:     return "Bench"
        case .rack:      return "Rack"
        case .pullUpBar: return "Pull-up bar"
        case .box:       return "Box"
        }
    }

    var glyph: AppGlyph {
        switch self {
        case .bench:     return .asset("equipment-bench")
        case .rack:      return .asset("equipment-rack")
        case .pullUpBar: return .asset("equipment-pullupbar")
        case .box:       return .asset("equipment-box")
        }
    }
}

/// The bars plates go on. Each has its own empty weight, which the user
/// can change in Training settings — Smith bars especially vary by brand.
enum BarKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case olympic
    case ezBar
    case trapBar
    case smith

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .olympic: return "Olympic barbell"
        case .ezBar:   return "EZ bar"
        case .trapBar: return "Trap bar"
        case .smith:   return "Smith machine bar"
        }
    }

    /// A typical bar in each unit. Not a conversion of each other: an
    /// Olympic bar is 20 kg or 45 lb depending on where it was made.
    func standardWeight(for unit: MeasurementUnit) -> Double {
        switch (self, unit) {
        case (.olympic, .metric):   return 20
        case (.olympic, .imperial): return 45
        case (.ezBar, .metric):     return 10
        case (.ezBar, .imperial):   return 25
        case (.trapBar, .metric):   return 25
        case (.trapBar, .imperial): return 55
        case (.smith, .metric):     return 15
        case (.smith, .imperial):   return 35
        }
    }
}
