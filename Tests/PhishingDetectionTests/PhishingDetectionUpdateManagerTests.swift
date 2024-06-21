import Foundation

import XCTest
@testable import PhishingDetection

class PhishingDetectionUpdateManagerTests: XCTestCase {
    var updateManager: PhishingDetectionUpdateManaging!
    var mockClient: MockPhishingDetectionClient!
    var mockDataProvider: MockPhishingDetectionDataProvider!
    let datasetFiles: [String] = ["hashPrefixes.json", "filterSet.json", "revision.txt"]
    var dataStore: PhishingDetectionDataStore!

    override func setUp() {
        super.setUp()
        mockClient = MockPhishingDetectionClient()
        mockDataProvider = MockPhishingDetectionDataProvider()
        dataStore = PhishingDetectionDataStore(dataProvider: mockDataProvider)
        updateManager = PhishingDetectionUpdateManager(client: mockClient, dataStore: dataStore)
    }

    override func tearDown() {
        mockClient = nil
        mockDataProvider = nil
        dataStore = nil
        updateManager = nil
        super.tearDown()
    }

    func clearDatasets() {
        for fileName in datasetFiles {
            let fileURL = dataStore.dataStore!.appendingPathComponent(fileName)
            do {
                try "".write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to clear contents of \(fileName): \(error)")
            }
        }
    }

    func testUpdateFilterSet() async {
        await updateManager.updateFilterSet()
        XCTAssertFalse(dataStore.filterSet.isEmpty, "Filter set should not be empty after update.")
    }

    func testLoadDataError() async {
        clearDatasets()
        await dataStore.loadData()
        // Error => reload from embedded data
        XCTAssertTrue(mockDataProvider.loadFilterSetCalled)
        XCTAssertTrue(mockDataProvider.loadHashPrefixesCalled)
    }

    func testUpdateHashPrefixes() async {
        await updateManager.updateHashPrefixes()
        XCTAssertFalse(dataStore.hashPrefixes.isEmpty, "Hash prefixes should not be empty after update.")
        XCTAssertEqual(dataStore.hashPrefixes, [
            "aa00bb11",
            "bb00cc11",
            "cc00dd11",
            "dd00ee11",
            "a379a6f6"
        ])
    }
//
//    func testCheckURL() async {
//        await service.updateHashPrefixes()
//        let trueResult = await service.isMalicious(url: URL(string: "https://example.com/bad/path")!)
//        XCTAssertTrue(trueResult, "URL check should return true for phishing URLs.")
//        let falseResult = await service.isMalicious(url: URL(string: "https://duck.com")!)
//        XCTAssertFalse(falseResult, "URL check should return false for normal URLs.")
//    }

    func testWriteAndLoadData() async {
        // Get and write data
        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()
        dataStore.writeData()

        // Clear data
        dataStore.hashPrefixes = []
        dataStore.filterSet = []

        // Load data
        await dataStore.loadData()
        XCTAssertFalse(dataStore.hashPrefixes.isEmpty, "Hash prefixes should not be empty after load.")
        XCTAssertFalse(dataStore.filterSet.isEmpty, "Filter set should not be empty after load.")
    }

    func testRevision1AddsData() async {
        dataStore.currentRevision = 1
        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()
        XCTAssertTrue(dataStore.filterSet.contains(where: { $0.hashValue == "testhash3" }), "Filter set should contain added data after update.")
        XCTAssertTrue(dataStore.hashPrefixes.contains("93e2435e"), "Hash prefixes should contain added data after update.")
    }

    func testRevision2AddsAndDeletesData() async {
        dataStore.currentRevision = 2
        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()
        XCTAssertFalse(dataStore.filterSet.contains(where: { $0.hashValue == "testhash2" }), "Filter set should not contain deleted data after update.")
        XCTAssertFalse(dataStore.hashPrefixes.contains("bb00cc11"), "Hash prefixes should not contain deleted data after update.")
        XCTAssertTrue(dataStore.hashPrefixes.contains("c0be0d0a6"))
    }

    func testRevision4AddsAndDeletesData() async {
        dataStore.currentRevision = 4
        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()
        XCTAssertTrue(dataStore.filterSet.contains(where: { $0.hashValue == "testhash5" }), "Filter set should contain added data after update.")
        XCTAssertFalse(dataStore.filterSet.contains(where: { $0.hashValue == "testhash3" }), "Filter set should not contain deleted data after update.")
        XCTAssertTrue(dataStore.hashPrefixes.contains("a379a6f6"), "Hash prefixes should contain added data after update.")
        XCTAssertFalse(dataStore.hashPrefixes.contains("aa00bb11"), "Hash prefixes should not contain deleted data after update.")
    }

}
