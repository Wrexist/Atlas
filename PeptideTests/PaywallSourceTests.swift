import XCTest
@testable import Peptide

final class PaywallSourceTests: XCTestCase {

    func test_funnelEventNames_carryTheSource() {
        XCTAssertEqual(PaywallSource.protocolLimit.viewedEvent, "paywall_viewed_protocolLimit")
        XCTAssertEqual(PaywallSource.export.purchasedEvent, "paywall_purchased_export")
        XCTAssertEqual(PaywallSource.generic.dismissedEvent, "paywall_dismissed_generic")
        XCTAssertEqual(PaywallSource.winBack.redeemedEvent, "paywall_redeemed_winBack")
    }

    /// `OnboardingFunnelTracker.recordEvent` truncates at 64 characters;
    /// a longer name would silently merge two sources in the snapshot.
    func test_everyEventName_fitsTheTrackerLimit() {
        for source in PaywallSource.allCases {
            for event in [source.viewedEvent, source.purchasedEvent, source.dismissedEvent, source.redeemedEvent] {
                XCTAssertLessThanOrEqual(event.count, 64, event)
            }
        }
    }

    func test_subhead_onlyAppearsUnderAHeadline() {
        for source in PaywallSource.allCases where source.headline == nil {
            XCTAssertNil(source.subhead, "\(source) has a subhead with no headline")
        }
    }

    func test_genericEntryPoints_keepTheDefaultHero() {
        XCTAssertNil(PaywallSource.generic.headline)
        XCTAssertNil(PaywallSource.profile.headline)
        XCTAssertNil(PaywallSource.deepLink.headline)
    }
}
