import XCTest
@testable import Peptide

final class ChartYDomainTests: XCTestCase {

    /// A 71–73 kg series must fill the plot, not sit on a zero-based axis.
    func test_padded_weightSeries_excludesZero() throws {
        let domain = try XCTUnwrap(ChartYDomain.padded([71, 72.5, 73], minimumPadding: 1))
        XCTAssertGreaterThan(domain.lowerBound, 60)
        XCTAssertLessThan(domain.lowerBound, 71)
        XCTAssertGreaterThan(domain.upperBound, 73)
        XCTAssertLessThan(domain.upperBound, 80)
    }

    func test_padded_flatSeries_usesMinimumPadding() throws {
        let domain = try XCTUnwrap(ChartYDomain.padded([58, 58, 58], minimumPadding: 2))
        XCTAssertEqual(domain, 56...60)
    }

    func test_padded_nonNegativeNearZero_neverDipsBelowZero() throws {
        let domain = try XCTUnwrap(ChartYDomain.padded([0.2, 3], minimumPadding: 1))
        XCTAssertEqual(domain.lowerBound, 0)
    }

    func test_padded_noFiniteValues_isNil() {
        XCTAssertNil(ChartYDomain.padded([], minimumPadding: 1))
        XCTAssertNil(ChartYDomain.padded([.nan, .infinity], minimumPadding: 1))
    }

    func test_padded_allZeroWithoutPadding_isNotEmpty() throws {
        let domain = try XCTUnwrap(ChartYDomain.padded([0, 0], minimumPadding: 0))
        XCTAssertGreaterThan(domain.upperBound, domain.lowerBound)
    }
}
