import Foundation

/// Where a `PaywallView` was opened from. Drives the contextual headline
/// above the offer and suffixes the funnel events
/// (`paywall_viewed_<source>` etc.) so conversion can be read per entry
/// point instead of as one blended number.
///
/// Copy here names the feature the user just reached for, nothing more —
/// no urgency, no numbers, no health values.
enum PaywallSource: String, CaseIterable, Identifiable, Sendable {
    case protocolLimit
    case biology
    case performanceAge
    case weeklyRecap
    case export
    case aiResearch
    case communityStack
    case profile
    case mealScanLimit
    case deepLink
    case winBack
    case generic

    /// Headline naming what the user was trying to do. `nil` for entry
    /// points with no specific feature in hand — the default hero stands
    /// alone there.
    var headline: String? {
        switch self {
        case .protocolLimit:  return String(localized: "Track unlimited protocols")
        case .biology:        return String(localized: "Unlock your recovery insights")
        case .performanceAge: return String(localized: "See your Biological Age")
        case .weeklyRecap:    return String(localized: "Get your weekly AI recap")
        case .export:         return String(localized: "Export your full history")
        case .aiResearch:     return String(localized: "Ask the AI research assistant")
        case .communityStack: return String(localized: "Use this as your protocol")
        case .mealScanLimit:  return String(localized: "Unlimited AI meal scans")
        case .winBack:        return String(localized: "Welcome back to Atlas Pro")
        case .profile, .deepLink, .generic: return nil
        }
    }

    /// One-line explanation under `headline`.
    var subhead: String? {
        switch self {
        case .protocolLimit:  return String(localized: "The free plan covers three active protocols. Pro removes the cap.")
        case .biology:        return String(localized: "HRV, resting heart rate and sleep, read together every morning.")
        case .performanceAge: return String(localized: "One number built from your recovery and training data.")
        case .weeklyRecap:    return String(localized: "A Sunday summary of your week, written for you.")
        case .export:         return String(localized: "Take every log with you as a file you own.")
        case .aiResearch:     return String(localized: "Questions answered with cited research.")
        case .communityStack: return String(localized: "Add it to your protocols and track it like your own.")
        case .mealScanLimit:  return String(localized: "Log every meal from a photo or barcode.")
        case .winBack:        return String(localized: "Pick up where you left off.")
        case .profile, .deepLink, .generic: return nil
        }
    }

    var id: String { rawValue }

    var viewedEvent: String { "paywall_viewed_\(rawValue)" }
    var purchasedEvent: String { "paywall_purchased_\(rawValue)" }
    var dismissedEvent: String { "paywall_dismissed_\(rawValue)" }
    var redeemedEvent: String { "paywall_redeemed_\(rawValue)" }
}
