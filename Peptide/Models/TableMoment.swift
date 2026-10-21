import Foundation

/// One shared table photographed in a single shot: the dishes the user
/// kept, cut out as stickers, plus how the meal went.
///
/// The nutrition lives where it always has — one `MealEntry` per dish in
/// the diary, sharing the dish's id — so editing or deleting a dish in
/// the diary needs nothing from here. This record only carries what the
/// diary has no slot for: the cut-outs, the rating and the note.
struct TableMoment: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var date: Date
    var category: MealCategory
    var note: String
    var dishes: [TableDish]

    init(id: UUID = UUID(), date: Date, category: MealCategory, note: String = "", dishes: [TableDish]) {
        self.id = id
        self.date = date
        self.category = category
        self.note = note
        self.dishes = dishes
    }

    var calories: Int { dishes.reduce(0) { $0 + $1.calories } }
    var proteinG: Int { dishes.reduce(0) { $0 + $1.proteinG } }

    /// The dishes still in the diary, carrying the diary's current name
    /// and numbers: an edit in the meal log is what the table shows.
    func logged(in entries: [MealEntry]) -> [TableDish] {
        let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return dishes.compactMap { dish in
            guard let entry = byID[dish.id] else { return nil }
            var current = dish
            current.name = entry.name
            current.calories = entry.calories
            current.proteinG = entry.proteinG
            return current
        }
    }
}

struct TableDish: Codable, Hashable, Identifiable, Sendable {
    /// Same id as the diary `MealEntry` this dish logged.
    let id: UUID
    var name: String
    var kind: DishKind
    /// Cut-out PNG in `TableMomentStore`'s folder. Nil when the file never
    /// made it to disk; the dish then draws as a plain plate.
    var stickerFilename: String?
    /// 0 is unrated, otherwise 1–5 stars.
    var rating: Int = 0
    var isFavorite = false
    var note = ""
    var calories: Int
    var proteinG: Int
}

/// The three buckets the review grid sorts a cut-out into.
enum DishKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case food, drink, other

    var id: Self { self }

    var label: String {
        switch self {
        case .food:  String(localized: "Food", comment: "Table scan — a cut-out dish is food")
        case .drink: String(localized: "Drinks", comment: "Table scan — a cut-out dish is a drink")
        case .other: String(localized: "Others", comment: "Table scan — a cut-out is neither food nor drink")
        }
    }
}
