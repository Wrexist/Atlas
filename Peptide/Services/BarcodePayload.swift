import Foundation

/// What the camera actually read, and what to do with it.
///
/// `DataScannerViewController` is configured with a bare `.barcode()`,
/// which means it already recognises every symbology iOS supports — QR,
/// Code 128, DataMatrix, PDF417, the lot. The app then handed whatever
/// came back straight to a validator that only accepts 8–14 digits, so
/// a QR code scanned perfectly and came back as "that barcode doesn't
/// look right." The camera was never the limitation; this is.
///
/// Two jobs, then. Recognise the payloads that *do* contain a product
/// code even when they aren't bare digits, and be honest about the ones
/// that don't.
enum BarcodePayload: Equatable, Sendable {

    /// Product codes worth trying, best guess first.
    ///
    /// One scan can legitimately map to several lookups. A US carton
    /// prints a 12-digit UPC-A that Open Food Facts may index under its
    /// 13-digit form; a shipping case prints an ITF-14 whose inner
    /// GTIN-13 is what the database actually holds. Trying one form and
    /// reporting "not found" was throwing away hits we already had.
    case gtin([String])

    /// A QR code carrying a web address — a promo code on a wrapper, a
    /// menu, a poster.
    case link(URL)

    /// Readable content that isn't a product code: a shipping label, a
    /// ticket, an internal store code.
    case text(String)

    /// Symbology identifiers some readers prepend to a GS1 payload.
    /// Stripped before parsing so `]C1` doesn't hide the AI behind it.
    private static let symbologyIdentifiers = ["]C1", "]e0", "]d2", "]Q3", "]J1"]

    /// FNC1 reaches the app as ASCII Group Separator.
    private static let groupSeparator: Character = "\u{1D}"

    static func classify(_ raw: String) -> BarcodePayload {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // GS1 first: a GS1 element string is long enough that no plain
        // 8–14 digit code can be mistaken for one, so this ordering
        // can't steal a straightforward scan.
        if let embedded = gs1GTIN(in: trimmed) {
            return .gtin(candidates(for: embedded))
        }

        if trimmed.count >= 8, trimmed.count <= 14, trimmed.allSatisfy(\.isNumber) {
            return .gtin(candidates(for: trimmed))
        }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           url.host?.isEmpty == false {
            return .link(url)
        }

        return .text(trimmed)
    }

    // MARK: - GTIN forms

    /// Every form of `code` worth asking the database about, in the
    /// order most likely to hit. Duplicates are dropped, so a code with
    /// no alternate forms yields exactly one candidate.
    static func candidates(for code: String) -> [String] {
        var ordered: [String] = []
        func add(_ candidate: String) {
            guard !candidate.isEmpty, !ordered.contains(candidate) else { return }
            ordered.append(candidate)
        }

        add(code)

        switch code.count {
        case 14:
            // ITF-14 case code. The indicator digit at the front and the
            // check digit at the back belong to the *case*, not to the
            // product — strip both and re-derive the product's own check
            // digit to get the GTIN-13 the database indexes.
            if let inner = gtin13(insideGTIN14: code) {
                add(inner)
                if inner.hasPrefix("0") { add(String(inner.dropFirst())) }
            }
        case 13:
            // A 13-digit code beginning with 0 is a UPC-A wearing an
            // EAN-13 coat; plenty of US products are filed under the
            // shorter form.
            if code.hasPrefix("0") { add(String(code.dropFirst())) }
        case 12:
            add("0" + code)
        default:
            break
        }

        return ordered
    }

    /// The GTIN-13 carried inside a GTIN-14, or nil when the input isn't
    /// 14 digits.
    static func gtin13(insideGTIN14 code: String) -> String? {
        guard code.count == 14, code.allSatisfy(\.isNumber) else { return nil }
        let base = String(code.dropFirst().dropLast())
        guard let check = checkDigit(for: base) else { return nil }
        return base + String(check)
    }

    /// GS1 mod-10 check digit for a code *without* its check digit.
    ///
    /// Weights alternate 3 and 1 starting from the rightmost digit of
    /// the base, which is why this walks the string in reverse rather
    /// than keying the weight off absolute position — the same formula
    /// then serves EAN-8, UPC-A, EAN-13 and GTIN-14 without a table.
    static func checkDigit(for base: String) -> Int? {
        guard !base.isEmpty, base.allSatisfy(\.isNumber) else { return nil }
        var sum = 0
        for (offset, character) in base.reversed().enumerated() {
            guard let digit = character.wholeNumberValue else { return nil }
            sum += digit * (offset.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - sum % 10) % 10
    }

    /// True when `code` is a well-formed GTIN — right length, all
    /// digits, check digit agrees.
    static func isValidGTIN(_ code: String) -> Bool {
        guard [8, 12, 13, 14].contains(code.count), code.allSatisfy(\.isNumber) else { return false }
        let base = String(code.dropLast())
        guard let expected = checkDigit(for: base), let actual = code.last?.wholeNumberValue else {
            return false
        }
        return expected == actual
    }

    // MARK: - GS1 element strings

    /// Pulls the GTIN out of a GS1-128 / GS1 DataMatrix payload.
    ///
    /// Deliberately narrow: this reads Application Identifier 01 (a
    /// fixed 14-digit GTIN) where the standard guarantees it can be
    /// found — at the head of the payload, or at the head of a
    /// separator-delimited segment. Full GS1 parsing means a table of
    /// every AI and its length rules, and getting that subtly wrong
    /// would mean looking up a batch number as if it were a product.
    /// A validated check digit is required so a coincidence can't
    /// masquerade as a hit.
    static func gs1GTIN(in payload: String) -> String? {
        var body = payload
        for identifier in symbologyIdentifiers where body.hasPrefix(identifier) {
            body.removeFirst(identifier.count)
            break
        }
        guard !body.isEmpty else { return nil }

        for segment in body.split(separator: groupSeparator) {
            guard segment.hasPrefix("01") else { continue }
            let rest = segment.dropFirst(2)
            guard rest.count >= 14 else { continue }
            let gtin = String(rest.prefix(14))
            guard isValidGTIN(gtin) else { continue }
            return gtin
        }
        return nil
    }
}
