import Foundation
import Security

/// A random UUID for this install, kept in the Keychain because Keychain
/// items outlive deleting the app on iOS, unlike UserDefaults and the App
/// Attest key. The proxy counts free-tier AI scans against it, so a
/// reinstall does not hand out a fresh allowance. It identifies nothing
/// about the user and only leaves the device on metered scans.
enum InstallIdentifier {
    /// Read or minted once per launch; `static let` initialisation is
    /// lazy and thread-safe.
    static let current: String = loadOrCreate()

    private static let service = "com.peptidesai.app.install"
    private static let account = "installID"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func loadOrCreate() -> String {
        if let existing = read() { return existing }
        let fresh = UUID().uuidString
        var add = baseQuery
        add[kSecValueData as String] = Data(fresh.utf8)
        // This-device-only: a restored backup on a new phone is a new
        // install. Readable after first unlock so a scan started from a
        // background-resumed app still finds it.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecSuccess { return fresh }
        if status == errSecDuplicateItem, let existing = read() { return existing }
        AppLog.persistence.error("Install ID not saved to Keychain: \(status, privacy: .public)")
        return fresh
    }

    private static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
