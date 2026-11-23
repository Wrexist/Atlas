import Foundation

/// The accent of the theme picked on the iPhone, as the two hex stops of
/// `AppThemeColor.primary`. The widgets and the Watch can't see
/// `ThemeManager`, so the phone hands it over: the widgets read it from
/// the App Group defaults, the Watch from `WatchData.accent`. Absent —
/// a fresh install, an older phone build — it is the brand emerald.
struct ThemeAccent: Codable, Equatable, Sendable {
    let light: UInt32
    let dark: UInt32

    static let emerald = ThemeAccent(light: 0x077A55, dark: 0x10B981)

    private static let defaultsKey = "themeAccent"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: AppGroup.identifier) }

    /// The accent the phone last stored, or emerald.
    static func stored() -> ThemeAccent {
        guard let data = defaults?.data(forKey: defaultsKey),
              let accent = try? JSONDecoder().decode(ThemeAccent.self, from: data) else { return .emerald }
        return accent
    }

    func store() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.defaults?.set(data, forKey: Self.defaultsKey)
    }
}
