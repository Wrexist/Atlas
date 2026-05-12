import Foundation

enum AppConstants {
    /// Live App Store listing for PeptideX (id6762042210, Sweden region
    /// — Apple's smart-app banner mechanism resolves the user's local
    /// store automatically, so the /se/ path doesn't pin the URL to one
    /// region for redirects).
    static let appStoreURL = URL(string: appStoreURLString) ?? URL(string: "https://apps.apple.com")!
    static let marketingHost = "peptidex.site"
    static let watermarkText = "Made with PeptideX"

    private static let appStoreURLString = "https://apps.apple.com/se/app/peptidex/id6762042210"
}
