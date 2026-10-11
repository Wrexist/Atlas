import Foundation

enum WatchFormat {
    /// "7h 12m", "45m": the compact form both the Sleep page and the
    /// Sleep complication use.
    static func duration(minutes: Int) -> String {
        Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
}
