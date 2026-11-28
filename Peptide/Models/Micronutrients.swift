import Foundation

/// The detail nutrients per 100 g of a food beyond the four macros, fibre
/// and sugar: six vitamins and minerals plus the fat breakdown, each in
/// the unit a nutrition label prints it in. Every value is optional: a
/// label or a scan that doesn't state one leaves it unknown, never an
/// invented zero. New fields keep a nil default so stored foods decode.
struct Micronutrients: Codable, Hashable, Sendable {
    var sodiumMg: Double? = nil
    var potassiumMg: Double? = nil
    var ironMg: Double? = nil
    var calciumMg: Double? = nil
    var vitaminDUg: Double? = nil
    var vitaminB12Ug: Double? = nil
    var saturatedFatG: Double? = nil
    var unsaturatedFatG: Double? = nil
    var cholesterolMg: Double? = nil

    /// Nil when nothing is known, so a food without micronutrient data
    /// stores no empty object.
    var nonEmpty: Micronutrients? {
        self == Micronutrients() ? nil : self
    }

    /// Each value this one lacks, taken from `other`. A stated value is
    /// never replaced, so label data keeps beating an estimate.
    func filling(from other: Micronutrients?) -> Micronutrients {
        guard let other else { return self }
        return Micronutrients(
            sodiumMg: sodiumMg ?? other.sodiumMg,
            potassiumMg: potassiumMg ?? other.potassiumMg,
            ironMg: ironMg ?? other.ironMg,
            calciumMg: calciumMg ?? other.calciumMg,
            vitaminDUg: vitaminDUg ?? other.vitaminDUg,
            vitaminB12Ug: vitaminB12Ug ?? other.vitaminB12Ug,
            saturatedFatG: saturatedFatG ?? other.saturatedFatG,
            unsaturatedFatG: unsaturatedFatG ?? other.unsaturatedFatG,
            cholesterolMg: cholesterolMg ?? other.cholesterolMg
        )
    }
}
