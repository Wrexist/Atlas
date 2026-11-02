import Foundation

/// Six vitamins and minerals per 100 g of a food, each in the unit a
/// nutrition label prints it in. Every value is optional: a label or a
/// scan that doesn't state one leaves it unknown, never an invented zero.
struct Micronutrients: Codable, Hashable, Sendable {
    var sodiumMg: Double? = nil
    var potassiumMg: Double? = nil
    var ironMg: Double? = nil
    var calciumMg: Double? = nil
    var vitaminDUg: Double? = nil
    var vitaminB12Ug: Double? = nil

    /// Nil when nothing is known, so a food without micronutrient data
    /// stores no empty object.
    var nonEmpty: Micronutrients? {
        self == Micronutrients() ? nil : self
    }
}
