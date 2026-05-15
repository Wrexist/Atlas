import Foundation

/// Detects when the user has crossed into a new timezone since the
/// last app launch, classifies the magnitude of the change, and
/// hands the caller a value the prompt UI can render directly.
///
/// Pure-function (with the small exception of reading
/// `TimeZone.current` and the user's profile-stored
/// last-known identifier). Caller is responsible for persisting
/// the new identifier after acting on the result so the prompt
/// only fires once per crossing.
enum TimezoneChangeDetector {

    /// Output of `detect(...)`. Carries enough context for the
    /// prompt sheet to render without re-reading any state.
    /// `Identifiable` so `sheet(item:)` can present it directly;
    /// the new-zone identifier is the natural id (each
    /// crossing-into-a-new-zone is unique).
    struct Change: Equatable, Identifiable, Sendable {
        let previousIdentifier: String
        let currentIdentifier: String
        /// Whole hours from previous → current. Positive = travelled
        /// east (clock moved forward); negative = travelled west.
        let hoursDelta: Int
        /// Whole minutes that don't fit cleanly into hour buckets
        /// (e.g. India Standard Time, +5:30). Surfaced separately so
        /// the prompt can show "+9 hours 30 minutes" honestly.
        let minutesRemainder: Int

        var id: String { currentIdentifier }

        /// Cleaned-up display name for a zone. `TimeZone.localizedName`
        /// is the friendliest user-facing string when available; falls
        /// back to the IANA identifier with the underscore stripped.
        var previousDisplayName: String { Self.displayName(for: previousIdentifier) }
        var currentDisplayName: String { Self.displayName(for: currentIdentifier) }

        /// Phrasing for the prompt body — handles signed direction +
        /// the minutes remainder cleanly so India / Newfoundland /
        /// Nepal users don't read "0 hours" by mistake.
        var deltaPhrase: String {
            let absHours = abs(hoursDelta)
            let absMinutes = abs(minutesRemainder)
            let hourPart = absHours == 1
                ? String(localized: "1 hour")
                : String(localized: "\(absHours) hours")
            let minutePart = absMinutes > 0
                ? String(localized: "\(absMinutes) minutes")
                : ""
            let magnitude = minutePart.isEmpty
                ? hourPart
                : String(
                    localized: "\(hourPart) \(minutePart)",
                    comment: "Travel-detection prompt — delta combining hours and remainder minutes."
                )
            return hoursDelta >= 0
                ? String(localized: "\(magnitude) ahead")
                : String(localized: "\(magnitude) behind")
        }

        private static func displayName(for identifier: String) -> String {
            guard let zone = TimeZone(identifier: identifier) else {
                return identifier.replacingOccurrences(of: "_", with: " ")
            }
            return zone.localizedName(for: .standard, locale: .current)
                ?? identifier.replacingOccurrences(of: "_", with: " ")
        }
    }

    /// Returns a `Change` when the user has crossed into a new zone
    /// with at least an hour of difference. Returns nil when:
    ///   • There's no previous identifier (fresh install).
    ///   • The identifier is unchanged.
    ///   • The offset difference is < 60 minutes (a DST transition
    ///     in the same zone, or a renamed identifier without a
    ///     real wall-clock shift).
    ///
    /// The 60-minute floor protects against the prompt firing on a
    /// DST roll where the user isn't really "travelling" — they're
    /// still in the same place, the clock just shifted.
    static func detect(
        previousIdentifier: String?,
        currentZone: TimeZone = .current,
        at referenceDate: Date = Date()
    ) -> Change? {
        guard let previousIdentifier,
              let previousZone = TimeZone(identifier: previousIdentifier),
              previousIdentifier != currentZone.identifier
        else { return nil }

        let prevOffset = previousZone.secondsFromGMT(for: referenceDate)
        let currOffset = currentZone.secondsFromGMT(for: referenceDate)
        let deltaSeconds = currOffset - prevOffset
        let totalMinutes = deltaSeconds / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        guard abs(totalMinutes) >= 60 else { return nil }

        return Change(
            previousIdentifier: previousIdentifier,
            currentIdentifier: currentZone.identifier,
            hoursDelta: hours,
            minutesRemainder: minutes
        )
    }
}
