import Foundation

import XCTest
@testable import PhishingDetection

class PhishingDetectionServiceTests: XCTestCase {
    var service: PhishingDetectionService!
    var mockClient: MockPhishingDetectionClient!
    var mockDataProvider: MockPhishingDetectionDataProvider!
    let datasetFiles: [String] = ["hashPrefixes.json", "filterSet.json", "revision.txt"]

    override func setUp() {
        super.setUp()
        mockClient = MockPhishingDetectionClient()
        mockDataProvider = MockPhishingDetectionDataProvider()
        service = PhishingDetectionService(apiClient: mockClient, dataProvider: mockDataProvider)
    }

    override func tearDown() {
        service = nil
        mockClient = nil
        mockDataProvider = nil
        super.tearDown()
    }
    
    func clearDatasets() {
        for fileName in datasetFiles {
            let fileURL = service.dataStore!.appendingPathComponent(fileName)
            do {
                try "".write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to clear contents of \(fileName): \(error)")
            }
        }
    }

    func testUpdateFilterSet() async {
        await service.updateFilterSet()
        XCTAssertFalse(service.filterSet.isEmpty, "Filter set should not be empty after update.")
    }
    
    func testLoadDataError() async {
        clearDatasets()
        await service.loadData()
        // Error => reload from embedded data and then update from server
        XCTAssertTrue(mockClient.updateFilterSetsWasCalled)
        XCTAssertTrue(mockClient.updateHashPrefixesWasCalled)
        XCTAssertTrue(mockDataProvider.loadFilterSetCalled)
        XCTAssertTrue(mockDataProvider.loadHashPrefixesCalled)
    }

    func testUpdateHashPrefixes() async {
        await service.updateHashPrefixes()
        XCTAssertFalse(service.hashPrefixes.isEmpty, "Hash prefixes should not be empty after update.")
        XCTAssertEqual(service.hashPrefixes, [
            "aa00bb11",
            "bb00cc11",
            "cc00dd11",
            "dd00ee11",
            "a379a6f6"
        ])
    }

    func testCheckURL() async {
        await service.updateHashPrefixes()
        let trueResult = await service.isMalicious(url: URL(string: "https://example.com/bad/path")!)
        XCTAssertTrue(trueResult, "URL check should return true for phishing URLs.")
        let falseResult = await service.isMalicious(url: URL(string: "https://duck.com")!)
        XCTAssertFalse(falseResult, "URL check should return false for normal URLs.")
    }

    func testWriteAndLoadData() async {
        // Get and write data
        await service.updateFilterSet()
        await service.updateHashPrefixes()
        service.writeData()
        
        // Clear data
        service.hashPrefixes = []
        service.filterSet = []
        
        // Load data
        await service.loadData()
        XCTAssertFalse(service.hashPrefixes.isEmpty, "Hash prefixes should not be empty after load.")
        XCTAssertFalse(service.filterSet.isEmpty, "Filter set should not be empty after load.")
    }
    
    func testRevision1AddsData() async {
        service.currentRevision = 1
        await service.updateFilterSet()
        await service.updateHashPrefixes()
        XCTAssertTrue(service.filterSet.contains(where: { $0.hashValue == "testhash3" }), "Filter set should contain added data after update.")
        XCTAssertTrue(service.hashPrefixes.contains("93e2435e"), "Hash prefixes should contain added data after update.")
    }

    func testRevision2AddsAndDeletesData() async {
        service.currentRevision = 2
        await service.updateFilterSet()
        await service.updateHashPrefixes()
        XCTAssertFalse(service.filterSet.contains(where: { $0.hashValue == "testhash2" }), "Filter set should not contain deleted data after update.")
        XCTAssertFalse(service.hashPrefixes.contains("bb00cc11"), "Hash prefixes should not contain deleted data after update.")
        XCTAssertTrue(service.hashPrefixes.contains("c0be0d0a6"))
    }

    func testRevision4AddsAndDeletesData() async {
        service.currentRevision = 4
        await service.updateFilterSet()
        await service.updateHashPrefixes()
        XCTAssertTrue(service.filterSet.contains(where: { $0.hashValue == "testhash5" }), "Filter set should contain added data after update.")
        XCTAssertFalse(service.filterSet.contains(where: { $0.hashValue == "testhash3" }), "Filter set should not contain deleted data after update.")
        XCTAssertTrue(service.hashPrefixes.contains("a379a6f6"), "Hash prefixes should contain added data after update.")
        XCTAssertFalse(service.hashPrefixes.contains("aa00bb11"), "Hash prefixes should not contain deleted data after update.")
    }

}
