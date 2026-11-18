import Foundation

/// The languages the app ships. The language itself is chosen in iOS
/// Settings (per-app language); the in-app picker only reports it and
/// links there.
enum AppLanguage: String, CaseIterable, Identifiable, Hashable {
    case english = "en"
    case swedish = "sv"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .english: "English"
        case .swedish: "Svenska"
        }
    }

    /// Languages this build has an `.lproj` for — English and Swedish
    /// (`CFBundleLocalizations` in `project.yml`).
    static var shipped: [AppLanguage] {
        allCases.filter { Bundle.main.localizations.contains($0.rawValue) }
    }

    /// The language the app's strings resolve in right now — the iOS
    /// per-app language, or the system one.
    static var current: AppLanguage? {
        Bundle.main.preferredLocalizations.first.flatMap(AppLanguage.init(rawValue:))
    }
}
