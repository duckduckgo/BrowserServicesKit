import Foundation

import XCTest
@testable import BrowserServicesKit
@testable import PhishingDetection

class PhishingDetectionServiceTests: XCTestCase {
    var service: PhishingDetectionService!

    override func setUp() {
        super.setUp()
        service = PhishingDetectionService()
        service.loadData() // Assuming you want to load test data
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    func testUpdateFilterSet() async {
        await service.updateFilterSet()
        XCTAssertFalse(service.filterSet.isEmpty, "Filter set should not be empty after update.")
    }

    func testUpdateHashPrefixes() async {
        await service.updateHashPrefixes()
        XCTAssertFalse(service.hashPrefixes.isEmpty, "Hash prefixes should not be empty after update.")
    }

    func testGetMatches() async {
        let matches = await service.getMatches(hashPrefix: "c51470e2")
        XCTAssertFalse(matches.isEmpty, "Should return matches for given hash prefix.")
        XCTAssertEqual(matches[0].hash, "c51470e2a70dd0e28d3049202883cf16113235a946bc7ce3e5b774c42348b67d")
        XCTAssertEqual(matches[0].url, "https://tv-licence_renew_easily_update-multiple-changes-6492a17447198.13000moveu.com.au/licence-home_cs_renewFilter-authorizationUpdate/index.php")
    }

    func testCheckURL() async {
        service.loadData()
        let trueResult = await service.isMalicious(url: "https://tv-licence_renew_easily_update-multiple-changes-6492a17447198.13000moveu.com.au/licence-home_cs_renewFilter-authorizationUpdate/index.php")
        XCTAssertTrue(trueResult, "URL check should return true for phishing URLs.")
        let falseResult = await service.isMalicious(url: "https://duck.com")
        XCTAssertFalse(falseResult, "URL check should return false for normal URLs.")
    }
//
//    func testInFilterSet() {
//        let filters = service.inFilterSet(hash: "somehash")
//        XCTAssertNotNil(filters, "Should return filters for given hash.")
//    }

    func testWriteAndLoadData() async {
        // Get and write data
        await service.updateFilterSet()
        await service.updateHashPrefixes()
        service.writeData()
        
        // Clear data
        service.hashPrefixes = []
        service.filterSet = []
        
        // Load data
        service.loadData()
        XCTAssertFalse(service.hashPrefixes.isEmpty, "Hash prefixes should not be empty after load.")
        XCTAssertFalse(service.filterSet.isEmpty, "Filter set should not be empty after load.")
    }
}
