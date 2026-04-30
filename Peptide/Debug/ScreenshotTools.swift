import Foundation

/// Build-flavour gate for the App Store screenshot tooling.
///
/// We need the seeder + Pro override + control panel to be reachable
/// from TestFlight (so screenshots can be captured on a real device)
/// but we never want them in App Store Release builds where end users
/// could trip the 7-tap trigger and overwrite their data.
///
/// Detection: TestFlight installs ship a `sandboxReceipt`, App Store
/// installs ship a real `receipt`. Reading the receipt path is reliable,
/// doesn't require any entitlement, and doesn't produce a network call.
///
/// In `#if DEBUG` (Xcode → Run, simulator) we always enable the tooling
/// regardless of receipt — locally-built apps may not have a receipt
/// at all.
enum ScreenshotTools {
    static var isAvailable: Bool {
        #if DEBUG
        return true
        #else
        guard let receiptURL = Bundle.main.appStoreReceiptURL else { return false }
        return receiptURL.lastPathComponent == "sandboxReceipt"
        #endif
    }
}
