@preconcurrency import AuthenticationServices
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// SwiftUI wrapper around the UIKit `ASAuthorizationAppleIDButton`.
/// Used in place of SwiftUI's `SignInWithAppleButton` because the SwiftUI
/// wrapper does not expose `presentationContextProvider`, which is required
/// for reliable presentation on iPad / Stage Manager / multi-scene layouts.
struct AppleSignInButton: View {
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    init(action: @escaping () -> Void) {
        self.action = action
    }

    var body: some View {
        // `ASAuthorizationAppleIDButton` fixes its style at init, so the
        // button is rebuilt when the scheme flips. White-on-dark /
        // black-on-light is Apple's own guidance.
        AppleIDButtonRepresentable(colorScheme: colorScheme, action: action)
            .id(colorScheme)
    }
}

private struct AppleIDButtonRepresentable: UIViewRepresentable {
    let colorScheme: ColorScheme
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(
            authorizationButtonType: .signIn,
            authorizationButtonStyle: colorScheme == .dark ? .white : .black
        )
        button.cornerRadius = Spacing.controlCornerRadius
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tap() { action() }
    }
}
