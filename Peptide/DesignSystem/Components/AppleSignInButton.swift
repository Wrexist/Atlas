@preconcurrency import AuthenticationServices
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// SwiftUI wrapper around the UIKit `ASAuthorizationAppleIDButton`.
/// Used in place of SwiftUI's `SignInWithAppleButton` because the SwiftUI
/// wrapper does not expose `presentationContextProvider`, which is required
/// for reliable presentation on iPad / Stage Manager / multi-scene layouts.
struct AppleSignInButton: UIViewRepresentable {
    var cornerRadius: CGFloat
    var action: () -> Void

    init(cornerRadius: CGFloat = 26, action: @escaping () -> Void) {
        self.cornerRadius = cornerRadius
        self.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(
            authorizationButtonType: .signIn,
            authorizationButtonStyle: .white
        )
        button.cornerRadius = cornerRadius
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        uiView.cornerRadius = cornerRadius
        context.coordinator.action = action
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tap() { action() }
    }
}
