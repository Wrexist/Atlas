import Foundation

/// The onboarding page sequence — single source of truth for order,
/// funnel names, and which pages may be skipped. Nine pages: related
/// asks share a page, and the personalised plan is the last page, so
/// the paywall it opens always follows a concrete result.
///
/// Removed from the old 16-page flow: the "try a set" demo (no data,
/// and the plan page now carries the value moment). Merged: sign-in
/// into name, experience into goal, equipment into schedule, health
/// into notifications, and projection into the Ready summary.
enum OnboardingStep: Int, CaseIterable, Comparable, Sendable {
    case welcome
    case name
    case goal
    case bodyMetrics
    case training
    case permissions
    case referral
    case disclaimer
    case plan

    /// Stable identifier recorded by `OnboardingFunnelTracker`, and the
    /// suffix of the `skip_<name>` event. Never derive these from the
    /// raw value — a reorder must not re-bucket the funnel.
    var funnelName: String {
        switch self {
        case .welcome:     return "welcome"
        case .name:        return "name"
        case .goal:        return "goal_and_experience"
        case .bodyMetrics: return "body_metrics"
        case .training:    return "training"
        case .permissions: return "permissions"
        case .referral:    return "referral"
        case .disclaimer:  return "disclaimer"
        case .plan:        return "plan"
        }
    }

    /// Skip is offered only where every value has a working default:
    /// permissions stay off (both re-askable from Profile and Biology),
    /// and the referral answers are optional attribution.
    var isSkippable: Bool {
        switch self {
        case .permissions, .referral: return true
        default:                      return false
        }
    }

    /// The plan summary's primary action opens the paywall. Only the
    /// last page does, so the offer never appears before the user has
    /// seen their own targets.
    var presentsPaywall: Bool { self == .plan }

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }

    static func < (lhs: OnboardingStep, rhs: OnboardingStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
