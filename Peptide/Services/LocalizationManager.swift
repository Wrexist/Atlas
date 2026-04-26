import Foundation
import SwiftUI

@Observable
final class LocalizationManager: @unchecked Sendable {
    static let shared = LocalizationManager()

    private static let defaultsKey = "preferredLanguageCode"

    var selectedCode: String? {
        didSet {
            if let code = selectedCode {
                UserDefaults.standard.set(code, forKey: Self.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
            }
        }
    }

    private init() {
        self.selectedCode = UserDefaults.standard.string(forKey: Self.defaultsKey)
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

    var layoutDirection: LayoutDirection {
        selectedLanguage?.isRTL == true ? .rightToLeft : .leftToRight
    }
}

enum AppLanguage: String, CaseIterable, Identifiable, Hashable {
    case english = "en"
    case spanish = "es"
    case chineseSimplified = "zh-Hans"
    case japanese = "ja"
    case german = "de"
    case french = "fr"
    case portugueseBrazil = "pt-BR"
    case korean = "ko"
    case russian = "ru"
    case arabic = "ar"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .english: "English"
        case .spanish: "Español"
        case .chineseSimplified: "简体中文"
        case .japanese: "日本語"
        case .german: "Deutsch"
        case .french: "Français"
        case .portugueseBrazil: "Português"
        case .korean: "한국어"
        case .russian: "Русский"
        case .arabic: "العربية"
        }
    }

    var englishName: String {
        switch self {
        case .english: "English"
        case .spanish: "Spanish"
        case .chineseSimplified: "Chinese (Simplified)"
        case .japanese: "Japanese"
        case .german: "German"
        case .french: "French"
        case .portugueseBrazil: "Portuguese (Brazil)"
        case .korean: "Korean"
        case .russian: "Russian"
        case .arabic: "Arabic"
        }
    }

    var flag: String {
        switch self {
        case .english: "🇺🇸"
        case .spanish: "🇪🇸"
        case .chineseSimplified: "🇨🇳"
        case .japanese: "🇯🇵"
        case .german: "🇩🇪"
        case .french: "🇫🇷"
        case .portugueseBrazil: "🇧🇷"
        case .korean: "🇰🇷"
        case .russian: "🇷🇺"
        case .arabic: "🇸🇦"
        }
    }

    var isRTL: Bool { self == .arabic }

    static func from(code: String?) -> AppLanguage? {
        guard let code else { return nil }
        return AppLanguage(rawValue: code)
    }
}
