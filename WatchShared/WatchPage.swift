import Foundation

/// The Watch app's pages. Shared with the complications, so a tap on one
/// opens the app on the page it summarises rather than on Today.
enum WatchPage: String, Hashable {
    case workout, today, recovery, sleep, nutrition, protocols

    private static let scheme = "atlaswatch"

    var url: URL { URL(string: "\(Self.scheme)://\(rawValue)")! }

    init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host() else { return nil }
        self.init(rawValue: host)
    }
}
