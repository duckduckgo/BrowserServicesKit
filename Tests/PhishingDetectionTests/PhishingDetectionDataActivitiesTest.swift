//
//  File.swift
//  
//
//  Created by Thom on 04/05/2024.
//

import Foundation
import XCTest
@testable import PhishingDetection

class PhishingDetectionDataActivitiesTests: XCTestCase {
    var mockDetectionService: MockPhishingDetector!
    var mockUpdateManager: MockPhishingDetectionUpdateManager!
    var activities: PhishingDetectionDataActivities!

    override func setUp() {
        super.setUp()
        mockDetectionService = MockPhishingDetector()
        mockUpdateManager = MockPhishingDetectionUpdateManager()
        activities = PhishingDetectionDataActivities(detectionService: mockDetectionService, hashPrefixInterval: 1, filterSetInterval: 1, phishingDetectionDataProvider: MockPhishingDetectionDataProvider(), updateManager: mockUpdateManager)
    }

    func testRun() async {
        let expectation = XCTestExpectation(description: "updateHashPrefixes and updateFilterSet completes")

        mockUpdateManager.completionHandler = {
            expectation.fulfill()
        }

        activities.start()

        await fulfillment(of: [expectation], timeout: 10.0)

        XCTAssertTrue(mockUpdateManager.didUpdateHashPrefixes)
        XCTAssertTrue(mockUpdateManager.didUpdateFilterSet)

    }
}
