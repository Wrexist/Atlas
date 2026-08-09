import Foundation

enum AppConstants {
    /// Live App Store listing for Atlas. The ID-only form carries no
    /// name slug, so a link we print into a share card can't spell the
    /// old "peptidex" brand at whoever scans it, and it survives any
    /// future listing rename. Apple resolves the user's local store
    /// from the ID, so it isn't pinned to one region either.
    static let appStoreURL = URL.staticHTTPS("https://apps.apple.com/app/id6762042210")
    static let marketingHost = "peptidex.site"
    static let watermarkText = "Made with Atlas"
}

extension URL {
    /// Build a URL from a string literal known to be well-formed at
    /// compile time. Lets us drop the `URL(string:)!` force-unwraps
    /// scattered through the codebase without lying to ourselves
    /// about whether the input might fail — these strings are
    /// hardcoded in the binary, so a parse failure is a programmer
    /// bug, not a runtime condition. Crashes early when violated.
    ///
    /// SwiftLint exempts this initializer from `force_unwrapping`
    /// via the disable comment below; every other call site goes
    /// through here.
    static func staticHTTPS(_ literal: StaticString) -> URL {
        let raw = literal.withUTF8Buffer { String(decoding: $0, as: UTF8.self) }
        guard let url = URL(string: raw) else {
            // Compile-time-known input — if URL.init rejects it, that's a
            // programmer bug at the literal site, not a runtime condition.
            // Crashing with the offending string is leagues better than a
            // bare `!` that says nothing at the EXC_BAD_INSTRUCTION
            // breakpoint.
            fatalError("AppConstants.staticHTTPS received a malformed URL literal: \(raw)")
        }
        return url
    }
}
