import Foundation

import XCTest
@testable import BrowserServicesKit
@testable import PhishingDetection

class PhishingDetectionServiceTests: XCTestCase {
    var service: PhishingDetectionService?

    override func setUp() {
        super.setUp()
        let mockClient = MockPhishingDetectionClient()
        service = PhishingDetectionService(apiClient: mockClient)
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    func testUpdateFilterSet() async {
        await service!.updateFilterSet()
        XCTAssertFalse(service!.filterSet.isEmpty, "Filter set should not be empty after update.")
    }

    func testUpdateHashPrefixes() async {
        await service!.updateHashPrefixes()
        XCTAssertFalse(service!.hashPrefixes.isEmpty, "Hash prefixes should not be empty after update.")
        XCTAssertEqual(service!.hashPrefixes, [
            "aa00bb11",
            "bb00cc11",
            "cc00dd11",
            "dd00ee11",
            "a379a6f6"
        ])
    }

    func testGetMatches() async {
        let matches = await service!.getMatches(hashPrefix: "aa00bb11")
        XCTAssertFalse(matches.isEmpty, "Should return matches for given hash prefix.")
        
        let expectedMatch = Match(hostname: "example.com", url: "https://example.com/mal", regex: ".", hash: "a379a6f6eeafb9a55e378c118034e2751e682fab9f2d30ab13d2125586ce1947")
        
        XCTAssertTrue(matches.contains(expectedMatch), "Set should contain the expected match.")
    }

    func testCheckURL() async {
        await service!.updateHashPrefixes()
        let trueResult = await service!.isMalicious(url: URL(string: "https://example.com/bad/path")!)
        XCTAssertTrue(trueResult, "URL check should return true for phishing URLs.")
        let falseResult = await service!.isMalicious(url: URL(string: "https://duck.com")!)
        XCTAssertFalse(falseResult, "URL check should return false for normal URLs.")
    }

    func testWriteAndLoadData() async {
        // Get and write data
        await service!.updateFilterSet()
        await service!.updateHashPrefixes()
        service!.writeData()
        
        // Clear data
        service!.hashPrefixes = []
        service!.filterSet = []
        
        // Load data
        service!.loadData()
        XCTAssertFalse(service!.hashPrefixes.isEmpty, "Hash prefixes should not be empty after load.")
        XCTAssertFalse(service!.filterSet.isEmpty, "Filter set should not be empty after load.")
    }
}
