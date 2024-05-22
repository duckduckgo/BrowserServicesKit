//
//  File.swift
//  
//
//  Created by Thom on 04/05/2024.
//

import Foundation
import XCTest
@testable import BrowserServicesKit
@testable import PhishingDetection

class PhishingDetectionDataActivitiesTest: XCTestCase {
    var dataActivities: PhishingDetectionDataActivities!
    var mockDetectionService: MockPhishingDetectionService = MockPhishingDetectionService()

    override func setUp() {
        super.setUp()
        dataActivities = PhishingDetectionDataActivities(detectionService: mockDetectionService)
    }

    func testDataActivitySchedulerRuns() async {
        let expectation1 = expectation(description: "Update filter set")
        let expectation2 = expectation(description: "Update hash prefixes")

        mockDetectionService.updateFilterSetCompletion = {
            expectation1.fulfill()
        }

        mockDetectionService.updateHashPrefixesCompletion = {
            expectation2.fulfill()
        }

        do {
            try await dataActivities.run()
            await waitForExpectations(timeout: 60, handler: nil)
            XCTAssertTrue(mockDetectionService.didUpdateFilterSet, "Filter set should be updated")
            XCTAssertTrue(mockDetectionService.didUpdateHashPrefixes, "Hash prefixes should be updated")
        } catch {
            XCTFail("Error updating Phishing Detection data")
        }
    }

}

