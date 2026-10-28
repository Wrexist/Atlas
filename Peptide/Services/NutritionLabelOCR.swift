import Foundation
import ImageIO
import UIKit
@preconcurrency import Vision

/// Reads a nutrition-facts label from a photo and produces a
/// `ScannedProduct` that flows through the same review-and-log path
/// as a barcode result. Used as a fallback from the barcode scanner's
/// `.notFound` state — when Open Food Facts doesn't know a product,
/// the user can photograph the label directly instead.
///
/// Architecture:
/// - `recognize(image:)` is the I/O wrapper. Runs Vision text
///   recognition off the main thread, then hands the recognised lines
///   to the pure parser.
/// - `NutritionLabelParser.parse(lines:)` is a pure function with no
///   UIKit/Vision dependency. It's where most of the testable logic
///   lives — given a list of label-line strings, return what macros
///   the parser could extract.
///
/// Scope limits intentionally taken in this v1:
/// - English-language labels only. Spanish/Swedish/etc. labels are
///   detected as text but the parser's keyword list doesn't match,
///   so a non-English label will return `.couldNotParse`.
/// - A per-serving panel is scaled to per-100g using the printed
///   serving grams, so one serving logs the printed numbers. When the
///   grams are unknown the values stay as printed and the review card
///   preselects 100 g, which again logs the printed numbers.
enum NutritionLabelOCR {

    enum OCRError: Error, LocalizedError, Equatable {
        case visionUnavailable
        case noTextFound
        case couldNotParse

        var errorDescription: String? {
            switch self {
            case .visionUnavailable:    String(localized: "Text recognition isn't available on this device.")
            case .noTextFound:          String(localized: "No text found in the photo. Try a clearer shot of the label.")
            case .couldNotParse:        String(localized: "We saw the label but couldn't read the calorie / macro values. Try a closer shot or use Edit on the next screen.")
            }
        }
    }

    /// Runs Vision text recognition on the supplied image and parses
    /// the result into a `ScannedProduct`. The product carries a
    /// synthetic `ocr:<uuid>` barcode so it doesn't collide with real
    /// barcodes in the cache or recents row, and so each OCR scan is
    /// independently identifiable.
    static func recognize(image: UIImage) async throws -> ScannedProduct {
        guard let cgImage = image.cgImage else { throw OCRError.visionUnavailable }

        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let lines = try await recognizeLines(from: cgImage, orientation: orientation)
        guard !lines.isEmpty else { throw OCRError.noTextFound }

        guard let parsed = NutritionLabelParser.parse(lines: lines) else {
            throw OCRError.couldNotParse
        }

        return ScannedProduct(
            barcode: "ocr:\(UUID().uuidString)",
            name: parsed.productName ?? String(localized: "Scanned label"),
            brand: nil,
            imageURL: nil,
            servingSizeText: parsed.servingSizeText,
            servingGrams: parsed.servingGrams,
            packageGrams: nil,
            per100g: parsed.per100g,
            nutriScore: nil,
            novaGroup: nil,
            fetchedAt: Date()
        )
    }

    /// Vision text recognition. Configured for accuracy over speed —
    /// nutrition labels are static photos, not a live camera stream,
    /// so the extra ~200ms is worth the better extraction. Sorted
    /// top-to-bottom so the parser can rely on label layout
    /// (calories appear before macros in standard FDA layout).
    private static func recognizeLines(
        from cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let sorted = observations.sorted { lhs, rhs in
                    // VN coordinates are bottom-up; flip so we read
                    // top-to-bottom the way humans (and labels) lay
                    // out information.
                    lhs.boundingBox.midY > rhs.boundingBox.midY
                }
                let lines = sorted.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false  // numbers + units, not prose
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private extension CGImagePropertyOrientation {
    /// `UIImage.cgImage` is the raw sensor bitmap; a portrait photo
    /// carries `.right` here, and Vision needs it to read the text upright.
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:            self = .up
        case .upMirrored:    self = .upMirrored
        case .down:          self = .down
        case .downMirrored:  self = .downMirrored
        case .left:          self = .left
        case .leftMirrored:  self = .leftMirrored
        case .right:         self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default:    self = .up
        }
    }
}

/// Pure parser for nutrition-label text. No I/O, no UIKit, no Vision —
/// gets a list of label lines (top to bottom), returns what it can
/// extract. Easy to unit-test with realistic line strings; the
/// `NutritionLabelOCR` wrapper just feeds it the Vision output.
enum NutritionLabelParser {

    struct ParsedLabel: Equatable {
        var productName: String?
        var servingSizeText: String?
        var servingGrams: Double?
        /// The values exactly as printed on the label.
        var nutriments: ScannedProduct.Nutriments
        /// True when the panel states its values per 100 g / 100 ml.
        var isPer100gPanel: Bool

        /// `nutriments` normalised to per-100g. A US-style panel prints
        /// per-serving values, which are scaled by the serving's grams.
        var per100g: ScannedProduct.Nutriments {
            guard !isPer100gPanel, let grams = servingGrams, grams > 0 else { return nutriments }
            let factor = 100 / grams
            return ScannedProduct.Nutriments(
                calories: nutriments.calories * factor,
                proteinG: nutriments.proteinG * factor,
                carbsG:   nutriments.carbsG * factor,
                fatG:     nutriments.fatG * factor,
                fiberG:   nutriments.fiberG.map { $0 * factor },
                sugarsG:  nutriments.sugarsG.map { $0 * factor },
                micros:   nutriments.micros.map { micros in
                    Micronutrients(
                        sodiumMg:     micros.sodiumMg.map { $0 * factor },
                        potassiumMg:  micros.potassiumMg.map { $0 * factor },
                        ironMg:       micros.ironMg.map { $0 * factor },
                        calciumMg:    micros.calciumMg.map { $0 * factor },
                        vitaminDUg:   micros.vitaminDUg.map { $0 * factor },
                        vitaminB12Ug: micros.vitaminB12Ug.map { $0 * factor }
                    )
                }
            )
        }
    }

    /// Returns nil if the label looks like it's not a nutrition facts
    /// panel at all (no recognised macro keywords). Returns a
    /// `ParsedLabel` with whatever fields we could extract; downstream
    /// code is responsible for handling missing macros (the user can
    /// always Edit before logging).
    ///
    /// Strategy: walk every line, extract the first number we find
    /// after each known macro keyword. Calories has its own pass
    /// because labels variously write it as `Calories 250`,
    /// `Energy 1050 kJ / 250 kcal`, `250 calories`, etc.
    static func parse(lines: [String]) -> ParsedLabel? {
        let normalized = lines.map { $0.lowercased() }

        let calories = parseCalories(in: normalized)
        let protein  = parseMacro(keyword: "protein",       in: normalized)
        let carbs    = parseMacro(keyword: "carbohydrate",  in: normalized)
                   ?? parseMacro(keyword: "carbs",          in: normalized)
        let fat      = parseFat(in: normalized)

        // Require at least calories OR one macro. A label with none
        // of these isn't really a nutrition panel — probably the
        // ingredients section or a marketing photo.
        let foundAny = [calories, protein, carbs, fat].contains { $0 != nil }
        guard foundAny else { return nil }

        let servingGrams = parseServingGrams(in: normalized)
        let servingSizeText = parseServingSizeText(in: lines)

        return ParsedLabel(
            productName: nil,           // future: pick from the largest-text line above the panel
            servingSizeText: servingSizeText,
            servingGrams: servingGrams,
            nutriments: ScannedProduct.Nutriments(
                calories: calories ?? 0,
                proteinG: protein ?? 0,
                carbsG:   carbs   ?? 0,
                fatG:     fat     ?? 0,
                fiberG:   parseMacro(keyword: "fiber", in: normalized)
                       ?? parseMacro(keyword: "fibre", in: normalized),
                sugarsG:  parseMacro(keyword: "sugar", in: normalized),
                micros:   parseMicros(in: normalized)
            ),
            isPer100gPanel: normalized.contains(where: isPer100gHeader)
        )
    }

    private static let per100gRegex = try? NSRegularExpression(
        pattern: #"per\s*100|\b100\s*(?:g|ml)\b"#
    )

    /// "Per 100 g", "100ml", "Nutrition per 100g" — the EU-style column
    /// header that means the values are already per 100.
    private static func isPer100gHeader(_ line: String) -> Bool {
        guard let regex = Self.per100gRegex else { return false }
        return regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    // MARK: - Macro extractors

    /// Matches `Protein 12g` / `Protein: 12 g` / `Protein  12.5  g` and
    /// returns the first numeric value following the keyword. Skips
    /// the percent-daily-value column when the value has a `%` suffix.
    private static func parseMacro(keyword: String, in lines: [String]) -> Double? {
        for line in lines {
            guard line.contains(keyword) else { continue }
            // Trim to the slice after the keyword so we don't match
            // numbers in unrelated parts of the line.
            guard let range = line.range(of: keyword) else { continue }
            let tail = line[range.upperBound...]
            if let value = firstNumber(in: String(tail)) {
                return value
            }
        }
        return nil
    }

    /// Special-cased: "fat" is a substring of "saturated fat" /
    /// "trans fat" / "polyunsaturated fat". To get the row for
    /// total fat, prefer lines starting with "fat" / "total fat" /
    /// "fat content" and fall through to a generic "fat" only as a
    /// last resort.
    private static func parseFat(in lines: [String]) -> Double? {
        let preferredPrefixes = ["total fat", "fat content", "fat"]
        for prefix in preferredPrefixes {
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix(prefix) else { continue }
                // Skip "saturated fat" / "trans fat" sub-rows.
                if prefix == "fat" {
                    if trimmed.hasPrefix("fat") && !trimmed.hasPrefix("fatty") {
                        let after = trimmed.dropFirst(prefix.count)
                        if let value = firstNumber(in: String(after)) {
                            return value
                        }
                    }
                    continue
                }
                let after = trimmed.dropFirst(prefix.count)
                if let value = firstNumber(in: String(after)) {
                    return value
                }
            }
        }
        return nil
    }

    // MARK: - Micronutrient extractors

    /// Sodium, potassium, iron, calcium, vitamin D and B12, in English
    /// and Swedish. EU panels print salt in grams instead of sodium
    /// (salt = sodium × 2.5).
    private static func parseMicros(in lines: [String]) -> Micronutrients? {
        let salt = parseAmount(keywords: ["salt"], in: lines).map { $0.inMilligrams(defaultUnit: "g") * 0.4 }
        return Micronutrients(
            sodiumMg:     parseAmount(keywords: ["sodium", "natrium"], in: lines)?.inMilligrams(defaultUnit: "mg") ?? salt,
            potassiumMg:  parseAmount(keywords: ["potassium", "kalium"], in: lines)?.inMilligrams(defaultUnit: "mg"),
            ironMg:       parseAmount(keywords: ["iron", "järn"], in: lines)?.inMilligrams(defaultUnit: "mg"),
            calciumMg:    parseAmount(keywords: ["calcium", "kalcium"], in: lines)?.inMilligrams(defaultUnit: "mg"),
            vitaminDUg:   parseAmount(keywords: ["vitamin d", "d-vitamin"], in: lines)?.inMicrograms(defaultUnit: "µg"),
            vitaminB12Ug: parseAmount(keywords: ["vitamin b12", "b12-vitamin", "b12"], in: lines)?.inMicrograms(defaultUnit: "µg")
        ).nonEmpty
    }

    struct LabelAmount: Equatable {
        let value: Double
        /// Lowercased unit as printed ("mg", "µg", "g", "iu"), nil if none.
        let unit: String?

        func inMilligrams(defaultUnit: String) -> Double {
            switch unit ?? defaultUnit {
            case "g":                    value * 1000
            case "µg", "μg", "mcg", "ug": value / 1000
            default:                     value
            }
        }

        /// Vitamin D in IU: 40 IU = 1 µg.
        func inMicrograms(defaultUnit: String) -> Double {
            switch unit ?? defaultUnit {
            case "mg":       value * 1000
            case "iu", "ie": value / 40
            default:         value
            }
        }
    }

    nonisolated(unsafe) private static let amountRegex = try? NSRegularExpression(
        pattern: #"([0-9]+(?:[.,][0-9]+)?)\s*(mg|µg|μg|mcg|ug|iu|ie|g)?(?![a-zà-ö0-9%])"#
    )

    /// The first amount after any of `keywords` as a whole word, with
    /// its unit. Skips percent-daily-value numbers.
    static func parseAmount(keywords: [String], in lines: [String]) -> LabelAmount? {
        guard let regex = amountRegex else { return nil }
        for keyword in keywords {
            let word = "(?<![a-zà-ö])" + NSRegularExpression.escapedPattern(for: keyword) + "(?![a-zà-ö0-9])"
            for line in lines {
                guard let range = line.range(of: word, options: .regularExpression) else { continue }
                let tail = String(line[range.upperBound...])
                let nsTail = tail as NSString
                for match in regex.matches(in: tail, range: NSRange(location: 0, length: nsTail.length)) {
                    let end = match.range.location + match.range.length
                    if end < nsTail.length, nsTail.character(at: end) == 37 /* % */ { continue }
                    let raw = nsTail.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")
                    guard let value = Double(raw) else { continue }
                    let unitRange = match.range(at: 2)
                    let unit = unitRange.location == NSNotFound ? nil : nsTail.substring(with: unitRange)
                    return LabelAmount(value: value, unit: unit)
                }
            }
        }
        return nil
    }

    private static func parseCalories(in lines: [String]) -> Double? {
        let rows = lines.filter { !isFootnote($0) }
        // Try the explicit "calories" keyword first — most US labels
        // surface a stand-alone "Calories 250" header above the
        // macro rows. Vision often returns the large FDA value as its
        // own observation, so a bare "Calories" row reads the next one.
        for (index, line) in rows.enumerated() where line.contains("calories") {
            if let value = energyNumber(in: line) { return value }
            let next = index + 1
            if next < rows.count, isBareNumber(rows[next]), let value = energyNumber(in: rows[next]) {
                return value
            }
        }
        // EU labels often write it as "Energy 1050 kJ / 250 kcal".
        // Prefer the kcal value if both are present.
        for line in rows where line.contains("kcal") {
            // Pull the number immediately preceding "kcal".
            let pieces = line.components(separatedBy: "kcal")
            if let head = pieces.first, let value = energyNumber(in: head, preferringLast: true) {
                return value
            }
        }
        // Last resort: kJ → kcal conversion. Same divisor the OFF
        // mapper uses (4.184 J/cal).
        for line in rows where line.contains("kj") || line.contains("energy") {
            if let value = energyNumber(in: line) {
                return value / 4.184
            }
        }
        return nil
    }

    /// The FDA "2,000 calories a day is used for general nutrition
    /// advice" footnote and the EU "Reference intake of an average adult
    /// (8400 kJ / 2000 kcal)" line both carry an energy figure that
    /// isn't the product's.
    private static func isFootnote(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("*")
            || line.contains("a day")
            || line.contains("daily value")
            || line.contains("reference intake")
    }

    /// "230" or "230 kcal" — a value row with no label of its own.
    private static func isBareNumber(_ line: String) -> Bool {
        line.replacingOccurrences(of: "kcal", with: "")
            .unicodeScalars
            .allSatisfy { !CharacterSet.letters.contains($0) }
    }

    /// Energy is never written with three decimals, so "1,050 kJ" is a
    /// thousands separator, not 1.05.
    private static func energyNumber(in text: String, preferringLast: Bool = false) -> Double? {
        firstNumber(in: text, preferringLast: preferringLast, commaGroupsThousands: true)
    }

    /// The number attached to a gram unit, not the first number on the line.
    ///
    /// This took whatever number came first, which on the standard FDA layout
    /// — "Serving size 1 cup (240g)" — is the portion *count*. Every US label
    /// written that way reported a 1-gram serving, and the review card does
    /// its per-serving maths from this.
    ///
    /// Anchoring to the unit also drops "1 muffin" to nil rather than 1 gram.
    /// The grams really are unknown there, and `servingGrams` is optional so
    /// the caller can say so; a fabricated 1 is worse than nothing.
    ///
    /// `mg` does not match — the `g` has to start the unit — so a
    /// "Serving size 500mg" line will not be read as 500 grams.
    private static func parseServingGrams(in lines: [String]) -> Double? {
        // "Serving size 1 cup (240g)" / "Serving size 30 g" / "Per 30g serving"
        for line in lines where line.contains("serving") || line.contains("portion") {
            guard let value = gramValue(in: line) else { continue }
            // Reject suspiciously large or zero serving sizes — OCR
            // sometimes picks up calorie counts in this row.
            if value > 0 && value < 2000 { return value }
        }
        return nil
    }

    private static let gramValueRegex = try? NSRegularExpression(
        pattern: #"(\d+(?:[.,]\d+)?)\s*g(?:ram|rams)?\b"#
    )

    private static func gramValue(in line: String) -> Double? {
        guard let regex = Self.gramValueRegex else { return nil }
        let ns = line as NSString
        let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
        guard let range = match?.range(at: 1) else { return nil }
        return Double(ns.substring(with: range).replacingOccurrences(of: ",", with: "."))
    }

    private static func parseServingSizeText(in lines: [String]) -> String? {
        // Surface the raw "Serving size: 1 cookie (30g)" line so the
        // review card can show it as a hint, even when we couldn't
        // pull a numeric grams value out of it.
        for line in lines {
            let lower = line.lowercased()
            if lower.contains("serving size") || lower.contains("per serving") {
                return line.trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    // MARK: - Number extraction

    /// Pre-compiled number regexes — the patterns are constant, so we
    /// build each once instead of per `firstNumber` call. `nonisolated(unsafe)`
    /// because `firstNumber` runs off the main actor during OCR and
    /// NSRegularExpression is thread-safe (matches the codebase's pattern
    /// for non-MainActor service statics).
    nonisolated(unsafe) private static let decimalNumberRegex = try? NSRegularExpression(pattern: "[0-9]+([.,][0-9]+)?")
    nonisolated(unsafe) private static let integerNumberRegex = try? NSRegularExpression(pattern: "[0-9]+")

    /// First numeric value in a line, optionally preferring the last
    /// match (for "1050 kJ / 250 kcal" we want 250, not 1050).
    /// Skips numbers immediately followed by `%` so we don't pick up
    /// the percent-daily-value column. A comma is a decimal mark unless
    /// `commaGroupsThousands` is set and three digits follow it.
    static func firstNumber(
        in text: String,
        allowingDecimals: Bool = true,
        preferringLast: Bool = false,
        commaGroupsThousands: Bool = false
    ) -> Double? {
        // Hoisted: this is called 30-50× per label scan, and recompiling
        // the regex each time was the bulk of the cost.
        guard let regex = allowingDecimals ? Self.decimalNumberRegex : Self.integerNumberRegex else { return nil }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        let candidates = matches.compactMap { match -> Double? in
            // Skip percent-daily-value columns: "12%".
            let endIndex = match.range.location + match.range.length
            if endIndex < nsText.length, nsText.character(at: endIndex) == 37 /* % */ {
                return nil
            }
            let raw = nsText.substring(with: match.range)
            if commaGroupsThousands, raw.range(of: #"^[1-9][0-9]{0,2},[0-9]{3}$"#, options: .regularExpression) != nil {
                return Double(raw.replacingOccurrences(of: ",", with: ""))
            }
            return Double(raw.replacingOccurrences(of: ",", with: "."))
        }
        return preferringLast ? candidates.last : candidates.first
    }
}
