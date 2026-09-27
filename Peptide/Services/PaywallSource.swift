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
        case .protocolLimit:  return "Track unlimited protocols"
        case .biology:        return "Unlock your recovery insights"
        case .performanceAge: return "See your Performance Age"
        case .weeklyRecap:    return "Get your weekly AI recap"
        case .export:         return "Export your full history"
        case .aiResearch:     return "Ask the AI research assistant"
        case .communityStack: return "Use this stack as a protocol"
        case .mealScanLimit:  return "Unlimited AI meal scans"
        case .winBack:        return "Welcome back to Atlas Pro"
        case .profile, .deepLink, .generic: return nil
        }
    }

    /// One-line explanation under `headline`.
    var subhead: String? {
        switch self {
        case .protocolLimit:  return "The free plan covers three active protocols. Pro removes the cap."
        case .biology:        return "HRV, resting heart rate and sleep, read together every morning."
        case .performanceAge: return "One number built from your recovery and training data."
        case .weeklyRecap:    return "A Sunday summary of your week, written for you."
        case .export:         return "Take every log with you as a file you own."
        case .aiResearch:     return "Questions answered with cited research."
        case .communityStack: return "Add it to your protocols and track it like your own."
        case .mealScanLimit:  return "Log every meal from a photo or barcode."
        case .winBack:        return "Pick up where you left off."
        case .profile, .deepLink, .generic: return nil
        }
    }

    var id: String { rawValue }

    var viewedEvent: String { "paywall_viewed_\(rawValue)" }
    var purchasedEvent: String { "paywall_purchased_\(rawValue)" }
    var dismissedEvent: String { "paywall_dismissed_\(rawValue)" }
    var redeemedEvent: String { "paywall_redeemed_\(rawValue)" }
}
