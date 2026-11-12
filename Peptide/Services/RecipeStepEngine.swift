import Foundation

/// Turns a library recipe's prose steps into steps a cook can act on: the
/// ingredients each step uses, with amounts scaled to the servings being
/// cooked, and any timed wait ("simmer for 8–10 minutes") as a timer the
/// step can start. Pure text work, no UI.
enum RecipeStepEngine {

    struct Step: Identifiable, Hashable, Sendable {
        /// Position in the method, from 0.
        let id: Int
        let text: String
        let ingredients: [StepIngredient]
        let timers: [StepTimer]
    }

    struct StepIngredient: Hashable, Sendable {
        let name: String
        let grams: Int
    }

    struct StepTimer: Hashable, Sendable {
        /// The short end of a range, so the cook checks early, not late.
        let seconds: Int
    }

    static func steps(for recipe: LibraryRecipe, servings: Int, locale: Locale) -> [Step] {
        let swedish = LibraryRecipe.isSwedish(locale)
        let names = recipe.ingredients.map { $0.displayName(locale: locale) }
        return recipe.displaySteps(locale: locale).enumerated().map { index, text in
            let used = ingredientIndices(in: text, names: names, swedish: swedish).map { position in
                let ingredient = recipe.ingredients[position]
                return StepIngredient(
                    name: names[position],
                    grams: RecipeLibraryEngine.displayGrams(RecipeLibraryEngine.grams(ingredient, servings: servings))
                )
            }
            return Step(id: index, text: text, ingredients: used, timers: timers(in: text))
        }
    }

    // MARK: - Ingredients

    /// Indices into `names` of the ingredients `step` mentions, in list
    /// order. Swedish names are compounds and inflect ("Kycklingbröst" is
    /// "kycklingen" in a step, "Fullkornsris" is "riset"), so a step word
    /// matches an ingredient word when a stem equals it, or is a whole part
    /// of the compound. A word that names one ingredient exactly ("lök")
    /// does not also pull in the compounds around it ("Vitlök").
    static func ingredientIndices(in step: String, names: [String], swedish: Bool) -> [Int] {
        let nameStems = names.map { words($0).map { stems(of: $0, swedish: swedish) } }
        var found: Set<Int> = []
        for word in words(step) where !stopWords.contains(word) {
            let stepStems = stems(of: word, swedish: swedish)
            let exact = names.indices.filter { index in
                nameStems[index].contains { !$0.isDisjoint(with: stepStems) }
            }
            if !exact.isEmpty {
                found.formUnion(exact)
                continue
            }
            found.formUnion(names.indices.filter { index in
                nameStems[index].contains { isCompoundPart(stepStems, of: $0) }
            })
        }
        return found.sorted()
    }

    /// "spenat" in "babyspenat", "kyckling" in "kycklingbröst": the stem
    /// must leave a real word beside it, so "färs" is not "färsk".
    private static func isCompoundPart(_ stepWord: Set<String>, of nameWord: Set<String>) -> Bool {
        stepWord.contains { part in
            part.count >= minimumStem && nameWord.contains { whole in
                (whole.hasPrefix(part) && whole.count - part.count >= minimumStem)
                    || (whole.hasSuffix(part) && whole.count - part.count >= 2)
            }
        }
    }

    private static let minimumStem = 3

    /// Lowercased runs of letters, three or more long.
    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { $0.count >= minimumStem }
    }

    /// The word itself plus every form left after dropping one inflection
    /// ending, keeping at least `minimumStem` letters.
    private static func stems(of word: String, swedish: Bool) -> Set<String> {
        let base = irregular[word] ?? word
        var out: Set<String> = [base]
        for suffix in swedish ? swedishSuffixes : englishSuffixes
        where base.hasSuffix(suffix) && base.count - suffix.count >= minimumStem {
            out.insert(String(base.dropLast(suffix.count)))
        }
        return out
    }

    private static let swedishSuffixes = ["arna", "erna", "orna", "ana", "an", "en", "et", "na", "er", "ar", "or", "n"]
    private static let englishSuffixes = ["es", "s", "d"]
    private static let irregular = ["morötter": "morot", "morötterna": "morot"]

    /// Cooking verbs and filler that would otherwise match an ingredient
    /// ("brown the mince" is not brown rice).
    private static let stopWords: Set<String> = [
        "med", "och", "till", "tills", "den", "det", "som", "att", "för", "per", "över", "under", "lite",
        "allt", "alla", "sida", "sidan", "minuter", "lock", "värme", "ugnen", "lådor", "låda", "panna",
        "pannan", "vatten", "servera", "skiva", "koka", "stek", "blanda", "lägg", "tillsätt", "små",
        "varm", "varmt", "kallt", "klart", "skvätt", "toppa", "rör", "ner", "upp", "sedan", "kött", "köttet",
        "the", "and", "with", "for", "until", "into", "over", "then", "each", "side", "minutes", "lid",
        "heat", "oven", "boxes", "box", "pan", "water", "serve", "slice", "cook", "fry", "mix", "add",
        "small", "warm", "cold", "done", "splash", "top", "stir", "brown", "season",
    ]

    // MARK: - Timers

    /// Every timed wait in the step, in reading order: "fem minuter",
    /// "8–10 minutes", "1 timme". Overnight and "until golden" have no
    /// number, so they get no timer.
    static func timers(in step: String) -> [StepTimer] {
        guard let regex = try? NSRegularExpression(pattern: timerPattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(step.startIndex..., in: step)
        return regex.matches(in: step, range: range).compactMap { match in
            guard let amountRange = Range(match.range(at: 1), in: step),
                  let unitRange = Range(match.range(at: 3), in: step),
                  let amount = number(String(step[amountRange]).lowercased())
            else { return nil }
            let seconds = Int((amount * Double(unitSeconds(String(step[unitRange]).lowercased()))).rounded())
            return seconds > 0 ? StepTimer(seconds: seconds) : nil
        }
    }

    private static func number(_ token: String) -> Double? {
        numberWords[token] ?? Double(token.replacingOccurrences(of: ",", with: "."))
    }

    private static func unitSeconds(_ unit: String) -> Int {
        if unit.hasPrefix("tim") || unit.hasPrefix("hour") { return 3600 }
        if unit.hasPrefix("sek") || unit.hasPrefix("sec") { return 1 }
        return 60
    }

    private static let numberWords: [String: Double] = [
        "en": 1, "ett": 1, "one": 1, "a": 1, "an": 1, "två": 2, "two": 2, "tre": 3, "three": 3,
        "fyra": 4, "four": 4, "fem": 5, "five": 5, "sex": 6, "six": 6, "sju": 7, "seven": 7,
        "åtta": 8, "eight": 8, "nio": 9, "nine": 9, "tio": 10, "ten": 10, "femton": 15, "fifteen": 15,
        "tjugo": 20, "twenty": 20, "trettio": 30, "thirty": 30, "fyrtio": 40, "forty": 40,
    ]

    private static let timerPattern: String = {
        let words = numberWords.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        let amount = #"(\d+(?:[.,]\d+)?|"# + words + ")"
        let unit = "(minuter|minuten|minutes|minute|minut|min|timmar|timme|timmen|hours|hour|sekunder|seconds|sek|sec)"
        return #"(?<![\p{L}\d])"# + amount + #"(?:\s*(?:–|-|to|till)\s*"# + amount + #")?\s*"# + unit + #"(?!\p{L})"#
    }()
}
