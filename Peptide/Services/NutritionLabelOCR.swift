import Foundation
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
/// - Per-serving values are returned as-is (treated as per-100g by
///   the downstream `ScannedProduct` shape). The Edit-before-log
///   sheet on the review card lets the user fix the math if they
///   ate a different portion than one serving. Future: parse
///   "Serving size: 30 g" + the per-100g column when both are present.
enum NutritionLabelOCR {

    enum OCRError: Error, LocalizedError, Equatable {
        case visionUnavailable
        case noTextFound
        case couldNotParse

        var errorDescription: String? {
            switch self {
            case .visionUnavailable:    "Text recognition isn't available on this device."
            case .noTextFound:          "No text found in the photo. Try a clearer shot of the label."
            case .couldNotParse:        "We saw the label but couldn't read the calorie / macro values. Try a closer shot or use Edit on the next screen."
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

        let lines = try await recognizeLines(from: cgImage)
        guard !lines.isEmpty else { throw OCRError.noTextFound }

        guard let parsed = NutritionLabelParser.parse(lines: lines) else {
            throw OCRError.couldNotParse
        }

        return ScannedProduct(
            barcode: "ocr:\(UUID().uuidString)",
            name: parsed.productName ?? "Scanned label",
            brand: nil,
            imageURL: nil,
            servingSizeText: parsed.servingSizeText,
            servingGrams: parsed.servingGrams,
            packageGrams: nil,
            per100g: parsed.nutriments,
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
    private static func recognizeLines(from cgImage: CGImage) async throws -> [String] {
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

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
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
        var nutriments: ScannedProduct.Nutriments
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
                sugarsG:  parseMacro(keyword: "sugar", in: normalized)
            )
        )
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

    private static func parseCalories(in lines: [String]) -> Double? {
        // Try the explicit "calories" keyword first — most US labels
        // surface a stand-alone "Calories 250" header above the
        // macro rows.
        for line in lines {
            guard line.contains("calories") else { continue }
            if let value = firstNumber(in: line) { return value }
        }
        // EU labels often write it as "Energy 1050 kJ / 250 kcal".
        // Prefer the kcal value if both are present.
        for line in lines where line.contains("kcal") {
            // Pull the number immediately preceding "kcal".
            let pieces = line.components(separatedBy: "kcal")
            if let head = pieces.first, let value = firstNumber(in: head, preferringLast: true) {
                return value
            }
        }
        // Last resort: kJ → kcal conversion. Same divisor the OFF
        // mapper uses (4.184 J/cal).
        for line in lines where line.contains("kj") || line.contains("energy") {
            if let value = firstNumber(in: line) {
                return value / 4.184
            }
        }
        return nil
    }

    private static func parseServingGrams(in lines: [String]) -> Double? {
        // "Serving size 30 g" / "Per 30g serving" / "Servings: 1 (30g)"
        for line in lines where line.contains("serving") || line.contains("portion") {
            if let value = firstNumber(in: line, allowingDecimals: true) {
                // Reject suspiciously large or zero serving sizes —
                // OCR sometimes picks up calorie counts in this row.
                if value > 0 && value < 2000 { return value }
            }
        }
        return nil
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

    /// First numeric value in a line, optionally preferring the last
    /// match (for "1050 kJ / 250 kcal" we want 250, not 1050).
    /// Skips numbers immediately followed by `%` so we don't pick up
    /// the percent-daily-value column.
    static func firstNumber(
        in text: String,
        allowingDecimals: Bool = true,
        preferringLast: Bool = false
    ) -> Double? {
        let pattern = allowingDecimals ? "[0-9]+([.,][0-9]+)?" : "[0-9]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        let candidates = matches.compactMap { match -> Double? in
            // Skip percent-daily-value columns: "12%".
            let endIndex = match.range.location + match.range.length
            if endIndex < nsText.length, nsText.character(at: endIndex) == 37 /* % */ {
                return nil
            }
            let raw = nsText.substring(with: match.range).replacingOccurrences(of: ",", with: ".")
            return Double(raw)
        }
        return preferringLast ? candidates.last : candidates.first
    }
}
