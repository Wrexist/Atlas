import SwiftUI

enum KeywordHighlighter {
    // Highlight priority: action > anatomical > biological.
    // Later passes overwrite earlier ones for overlapping matches.
    // Within each list, longer/more-specific phrases are listed before
    // shorter substrings so both get highlighted independently.

    private static let biologicalKeywords = [
        "amino acids", "pentadecapeptide", "heptapeptide", "tripeptide",
        "tetrapeptide", "neurotrophic factor", "growth hormone",
        "thymosin beta-4", "Drug Affinity Complex", "insulin-like",
        "telomerase", "telomere", "collagen", "cathelicidin",
        "T-cells", "ghrelin", "somatostatin",
        "BDNF", "HGF", "IGF-1", "GHRH", "ACTH",
        "BPC-157", "TB-500", "GHK-Cu", "CJC-1295", "LL-37",
        "AOD-9604", "Semax", "Selank", "Epitalon",
        "Ipamorelin", "Tesamorelin", "Dihexa",
    ]

    private static let anatomicalKeywords = [
        "central nervous system", "gastrointestinal tract",
        "blood-brain barrier", "gastric juice",
        "connective tissue", "endocrine system",
        "skeletal muscle", "cardiovascular",
        "nervous system", "immune system",
        "pituitary gland", "pineal gland", "thymus gland",
        "hypothalamus",
    ]

    private static let actionKeywords = [
        "blood vessel formation", "anti-inflammatory",
        "cell migration", "wound healing", "tissue repair",
        "neuroprotective", "antimicrobial", "regenerative",
        "anxiolytic", "lipolysis", "anabolic", "protective",
        "accelerates", "upregulates", "stimulates",
        "modulates", "activates", "promotes", "enhances", "inhibits",
        "healing",
    ]

    private static let semiboldBody = Font.system(size: 17, weight: .semibold)

    static func highlight(_ text: String, accentColor: Color) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.font = AppFont.body
        attributed.foregroundColor = AppColor.textSecondary

        applyHighlights(to: &attributed, in: text, keywords: biologicalKeywords, color: AppColor.accentLight)
        applyHighlights(to: &attributed, in: text, keywords: anatomicalKeywords, color: AppColor.textHighlight)
        applyHighlights(to: &attributed, in: text, keywords: actionKeywords, color: accentColor)

        return attributed
    }

    private static func applyHighlights(
        to attributed: inout AttributedString,
        in text: String,
        keywords: [String],
        color: Color
    ) {
        for keyword in keywords {
            var searchStart = text.startIndex
            while let range = text.range(of: keyword, options: .caseInsensitive, range: searchStart..<text.endIndex) {
                // Word boundary check: reject matches that are part of a longer word.
                // Letters on either side indicate the match is a substring, not a word.
                let before = range.lowerBound > text.startIndex
                    ? text[text.index(before: range.lowerBound)]
                    : Character(" ")
                let after = range.upperBound < text.endIndex
                    ? text[range.upperBound]
                    : Character(" ")

                if before.isLetter || after.isLetter {
                    searchStart = range.upperBound
                    continue
                }

                if let attrRange = AttributedString.Index(range.lowerBound, within: attributed),
                   let attrEnd = AttributedString.Index(range.upperBound, within: attributed) {
                    attributed[attrRange..<attrEnd].foregroundColor = color
                    attributed[attrRange..<attrEnd].font = semiboldBody
                }
                searchStart = range.upperBound
            }
        }
    }
}
