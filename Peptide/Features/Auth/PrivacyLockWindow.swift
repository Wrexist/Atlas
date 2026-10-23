import SwiftUI
import UIKit

/// Shows the biometric lock, or an opaque privacy cover, in its own
/// window above the app. A separate window is the only surface that sits
/// over every sheet and full-screen cover, so locking hides all of it
/// without tearing down the UI — the user lands back where they were.
@MainActor
final class PrivacyLockWindow {
    enum Cover: Equatable {
        /// Face ID / passcode prompt; the app stays covered until unlock.
        case lock
        /// Plain cover while the app is inactive, so the app-switcher
        /// snapshot never shows health data.
        case snapshot
    }

    static let shared = PrivacyLockWindow()

    private var window: UIWindow?
    private var shown: Cover?

    private init() {}

    func show(_ cover: Cover, content: some View) {
        guard cover != shown,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        // The cover never becomes key, so a focused field underneath would
        // keep the keyboard up over it and keep taking keystrokes (B092).
        for appWindow in scene.windows where appWindow !== self.window {
            appWindow.endEditing(true)
        }
        let window = window ?? UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        window.rootViewController = UIHostingController(rootView: content)
        // The app stays mounted underneath; modal keeps VoiceOver and
        // Switch Control from reaching it through the cover.
        window.accessibilityViewIsModal = true
        // Visible but never key, so the app's own window keeps key status
        // and its presentation checks keep working after unlock.
        window.isHidden = false
        self.window = window
        shown = cover
    }

    func hide() {
        window?.isHidden = true
        window = nil
        shown = nil
    }
}

/// The opaque stand-in behind `PrivacyLockWindow.Cover.snapshot`.
struct PrivacyCoverView: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(AppFont.scaled(48, relativeTo: .largeTitle))
            .foregroundStyle(AppColor.accentPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.background)
            .accessibilityHidden(true)
    }
}
