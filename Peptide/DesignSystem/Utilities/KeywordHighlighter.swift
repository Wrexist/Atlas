import SwiftUI

enum KeywordHighlighter {
    private enum KeywordCategory {
        case biological
        case anatomical
        case action
    }

    private static let biologicalKeywords = [
        "amino acids", "pentadecapeptide", "heptapeptide", "tripeptide",
        "tetrapeptide", "peptide", "protein", "enzyme", "receptor",
        "hormone", "neurotrophic factor", "telomerase", "telomere",
        "collagen", "T-cells", "cathelicidin", "BDNF", "HGF",
        "IGF-1", "GHRH", "ACTH", "melatonin", "thymosin beta-4",
        "growth hormone", "ghrelin", "somatostatin", "insulin-like",
        "Drug Affinity Complex", "BPC-157", "TB-500", "GHK-Cu",
        "Semax", "Selank", "Epitalon", "LL-37", "CJC-1295",
        "Ipamorelin", "AOD-9604", "Tesamorelin", "Dihexa",
    ]

    private static let anatomicalKeywords = [
        "gastric juice", "blood-brain barrier", "gastrointestinal tract",
        "nervous system", "immune system", "cardiovascular",
        "pineal gland", "thymus gland", "pituitary gland",
        "skeletal muscle", "connective tissue", "endocrine system",
        "central nervous system", "hypothalamus",
    ]

    private static let actionKeywords = [
        "healing", "regenerative", "neuroprotective", "anti-inflammatory",
        "antimicrobial", "anxiolytic", "lipolysis", "anabolic",
        "accelerates", "stimulates", "promotes", "enhances",
        "activates", "inhibits", "upregulates", "modulates",
        "protective", "wound healing", "tissue repair",
        "cell migration", "blood vessel formation",
    ]

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
                // Word boundary check for short keywords
                if keyword.count < 6 {
                    let before = range.lowerBound > text.startIndex
                        ? text[text.index(before: range.lowerBound)]
                        : Character(" ")
                    let after = range.upperBound < text.endIndex
                        ? text[range.upperBound]
                        : Character(" ")

                    let isWordBoundary = !before.isLetter && !after.isLetter
                    if !isWordBoundary {
                        searchStart = range.upperBound
                        continue
                    }
                }

                if let attrRange = AttributedString.Index(range.lowerBound, within: attributed),
                   let attrEnd = AttributedString.Index(range.upperBound, within: attributed) {
                    attributed[attrRange..<attrEnd].foregroundColor = color
                    attributed[attrRange..<attrEnd].font = AppFont.body.weight(.semibold)
                }
                searchStart = range.upperBound
            }
        }
    }
}
