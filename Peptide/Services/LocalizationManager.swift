import Foundation
import SwiftUI

/// The user's language override, observed by SwiftUI.
///
/// **Concurrency invariant: main actor only** — same situation as
/// `ThemeManager`, and the same stopgap: `@unchecked Sendable` plus a debug
/// assertion on every mutation, until the isolation can be stated as
/// `@MainActor` against a compiler.
@Observable
final class LocalizationManager: @unchecked Sendable {
    static let shared = LocalizationManager()

    private static let defaultsKey = "preferredLanguageCode"

    var selectedCode: String? {
        didSet {
            assertMainActor()
            if let code = selectedCode {
                UserDefaults.standard.set(code, forKey: Self.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
            }
        }
    }

    private init() {
        // A code saved while the picker offered languages the build does not
        // ship would leave the app half in that language, so drop it.
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey)
        self.selectedCode = AppLanguage.shipped.contains { $0.rawValue == stored } ? stored : nil
    }

    var selectedLanguage: AppLanguage? {
        AppLanguage.from(code: selectedCode)
    }

    var effectiveLocale: Locale {
        if let code = selectedCode {
            return Locale(identifier: code)
        }
        return .autoupdatingCurrent
    }
}

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

    var englishName: String {
        switch self {
        case .english: "English"
        case .swedish: "Swedish"
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

    static func from(code: String?) -> AppLanguage? {
        guard let code else { return nil }
        return AppLanguage(rawValue: code)
    }
}
