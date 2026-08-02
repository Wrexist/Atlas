import Foundation

/// Traps in debug builds when a main-actor-only invariant is violated.
///
/// Some singletons are read from so many places that stating their isolation
/// in the type system is a large, compiler-gated refactor — see the note on
/// `ThemeManager`. Those types carry `@unchecked Sendable`, and this is what
/// makes that claim honest: the invariant is checked on every mutation, so a
/// stray background write surfaces immediately with a stack trace instead of
/// corrupting the `@Observable` registrar silently under load.
///
/// Compiled out of release builds — `assert` is a no-op there, and the check
/// itself sits behind `#if DEBUG` so `Thread.isMainThread` isn't consulted in
/// shipping code.
///
/// This is a stopgap, not a design. When a type's isolation can be expressed
/// as `@MainActor`, do that instead and delete the call.
@inlinable
func assertMainActor(
    _ message: @autoclosure () -> String = "must be used from the main actor",
    file: StaticString = #fileID,
    line: UInt = #line
) {
    #if DEBUG
    assert(Thread.isMainThread, message(), file: file, line: line)
    #endif
}
