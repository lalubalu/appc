import XCTest
import CoreLocation
@testable import Verdure

@MainActor final class PartnerDiscoveryTests: XCTestCase {
    func testNearbySortAndMissingLocationFallback() {
        let perks = EconomyService.parseCatalog(["perks": [
            ["id": "far", "title": "Far", "latitude": 37.5, "longitude": -121.8863],
            ["id": "missing", "title": "Missing coordinates"],
            ["id": "near", "title": "Near", "latitude": 37.339, "longitude": -121.8863],
        ]]).perks
        XCTAssertEqual(PartnerPerk.sortedNearby(perks, origin: nil).map(\.id), ["far", "missing", "near"])
        let sorted = PartnerPerk.sortedNearby(perks, origin: CLLocation(latitude: 37.3382, longitude: -121.8863))
        XCTAssertEqual(sorted.map(\.id), ["near", "far", "missing"])
    }

    func testNearbySortPreservesServerOrderForEqualOrInvalidDistances() {
        let perks = EconomyService.parseCatalog(["perks": [
            ["id": "first", "title": "First", "latitude": 37.3382, "longitude": -121.8863],
            ["id": "second", "title": "Second", "latitude": 37.3382, "longitude": -121.8863],
            ["id": "invalid", "title": "Invalid", "latitude": 999.0, "longitude": -121.8863],
            ["id": "absent", "title": "Absent"],
        ]]).perks
        XCTAssertEqual(PartnerPerk.sortedNearby(perks, origin: CLLocation(latitude: 37.3382, longitude: -121.8863)).map(\.id),
                       ["first", "second", "invalid", "absent"])
    }
}
