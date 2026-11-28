import StoreKit
import SwiftUI
import UIKit

/// Shake the phone in a TestFlight or debug build to write a note about
/// the screen you're on. The note sheet is presented over whatever is
/// showing, sheets included, after the screenshot is taken.
@MainActor
enum FieldNotePresenter {
    /// The note sheet while it is up. Weak, so however the sheet goes
    /// away (Save, Cancel, swipe, its presenter dismissed) a shake works
    /// again without any flag to reset.
    private static weak var current: UIViewController?
    private static var isTestBuild: Bool?

    static func shakeDetected(in window: UIWindow) {
        guard current == nil else { return }
        Task { @MainActor in
            guard await testBuild() else { return }
            present(over: window)
        }
    }

    private static func present(over window: UIWindow) {
        guard current == nil,
              let top = topViewController(from: window.rootViewController),
              top.presentedViewController == nil, !top.isBeingPresented, !top.isBeingDismissed
        else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        let screen = screenName(in: window)
        Haptics.impact(.medium)
        let presented = PresentedSheet()
        let sheet = UIHostingController(
            rootView: FieldNoteSheet(screen: screen, screenshot: screenshot) {
                presented.controller?.dismiss(animated: true)
            }
            // Outside the app's SwiftUI root, so the in-app appearance
            // and accent are applied here.
            .preferredColorScheme(ThemeManager.shared.displayMode.preferredScheme)
            .tint(AppColor.accentPrimary)
        )
        presented.controller = sheet
        current = sheet
        top.present(sheet, animated: true)
    }

    /// TestFlight builds run with a sandbox App Store environment; debug
    /// builds always allow it. Only an answer is cached: a check that
    /// fails (offline) is tried again on the next shake.
    private static func testBuild() async -> Bool {
        if let isTestBuild { return isTestBuild }
        #if DEBUG
        isTestBuild = true
        return true
        #else
        do {
            let verification = try await AppTransaction.shared
            guard case .verified(let transaction) = verification else { return false }
            let result = transaction.environment == .sandbox
            isTestBuild = result
            return result
        } catch {
            return false
        }
        #endif
    }

    private static func topViewController(from root: UIViewController?) -> UIViewController? {
        var top = root
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    /// The selected tab's title, plus "sheet" when something is presented
    /// over it. Enough to find the screen again from the note.
    private static func screenName(in window: UIWindow) -> String {
        let tab = tabBarController(in: window.rootViewController)?.selectedViewController?.tabBarItem.title
        let base = tab ?? "App"
        return window.rootViewController?.presentedViewController == nil ? base : "\(base) · sheet"
    }

    private static func tabBarController(in controller: UIViewController?) -> UITabBarController? {
        guard let controller else { return nil }
        if let tabs = controller as? UITabBarController { return tabs }
        for child in controller.children {
            if let found = tabBarController(in: child) { return found }
        }
        return nil
    }

    /// Lets the sheet's buttons dismiss the controller that hosts it.
    private final class PresentedSheet {
        weak var controller: UIViewController?
    }
}

extension UIWindow {
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake else { return }
        FieldNotePresenter.shakeDetected(in: self)
    }
}
