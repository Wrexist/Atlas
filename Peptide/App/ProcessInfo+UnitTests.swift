import Foundation

extension ProcessInfo {
    /// True when this process is the host app for XCTest unit tests. Tests
    /// run inside the full app, so launch work that would reach RevenueCat,
    /// the CloudKit store or the network checks this first. UI tests drive
    /// a separate app process that never has this variable.
    var isRunningUnitTests: Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}
