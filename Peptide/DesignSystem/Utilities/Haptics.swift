import UIKit

/// Centralised haptic vocabulary that honours the user's "Haptic
/// Feedback" setting in exactly one place.
///
/// Before this, every call site repeated the same guard:
///
/// ```swift
/// if profile.hapticFeedbackEnabled {
///     UIImpactFeedbackGenerator(style: .light).impactOccurred()
/// }
/// ```
///
/// That meant the toggle had to be threaded through every view, and a
/// single missed guard shipped a stray buzz with the setting off.
/// `Haptics` reads the preference itself, so call sites collapse to a
/// one-liner that reads like a sentence: `Haptics.impact(.light)`,
/// `Haptics.selection()`, `Haptics.success()`.
///
/// The preference is resolved through a closure wired once at launch
/// (`configure(isEnabled:)`) rather than a cached `Bool`, so it stays
/// live — a CloudKit sync or backup restore that flips
/// `UserProfile.hapticFeedbackEnabled` is reflected on the very next
/// haptic without a separate "keep the mirror in sync" code path.
///
/// `@MainActor` because every UIKit feedback API must run on the main
/// thread. Generators allocate a system resource on first use and
/// Apple advises against holding them across events, so each call
/// constructs its own — cheap, and the documented usage.
@MainActor
enum Haptics {
    /// Resolves the user's current Haptic Feedback preference. Defaults
    /// to `true` to match `UserProfile`'s default, so a haptic fired
    /// before `configure` runs still does the expected thing.
    private static var resolveEnabled: () -> Bool = { true }

    /// Wire the live preference lookup once at app launch. Pass a
    /// closure that reads `UserProfile.hapticFeedbackEnabled` so the
    /// value is always current.
    static func configure(isEnabled: @escaping () -> Bool) {
        resolveEnabled = isEnabled
    }

    private static var isEnabled: Bool { resolveEnabled() }

    /// Light positional tick for selection changes — chip taps, ring
    /// taps, segment switches. The everyday "I registered that" feel.
    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Physical impact at the given weight. `.light` for routine taps,
    /// `.medium` / `.heavy` for commits the user should feel land.
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// Outcome notification — the system `.success` / `.warning` /
    /// `.error` vocabulary users already recognise from iOS flows.
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    /// Sentence-reading conveniences over `notify(_:)`.
    static func success() { notify(.success) }
    static func warning() { notify(.warning) }
    static func error()   { notify(.error) }
}
