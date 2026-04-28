import Foundation
import OSLog

/// Centralized os.Logger instances per subsystem. Use these instead of ad-hoc
/// `Logger(subsystem:...)` calls so categories stay consistent in Console.app.
enum AppLog {
    private static let subsystem = "com.peptidesai.app"

    static let persistence   = Logger(subsystem: subsystem, category: "Persistence")
    static let swiftData     = Logger(subsystem: subsystem, category: "SwiftData")
    static let healthKit     = Logger(subsystem: subsystem, category: "HealthKit")
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    static let auth          = Logger(subsystem: subsystem, category: "Auth")
    static let storeKit      = Logger(subsystem: subsystem, category: "StoreKit")
    static let export        = Logger(subsystem: subsystem, category: "Export")
    static let achievements  = Logger(subsystem: subsystem, category: "Achievements")
    static let biometrics    = Logger(subsystem: subsystem, category: "Biometrics")
    static let database      = Logger(subsystem: subsystem, category: "Database")
}
