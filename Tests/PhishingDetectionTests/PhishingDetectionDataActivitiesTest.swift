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
        let expectation = XCTestExpectation(description: "HashPrefixDataActivity should run and update hash prefixes")

        Task {
            await dataActivities.run()
            XCTAssertTrue(mockDetectionService.didUpdateHashPrefixes, "Hash prefixes should be updated")
            expectation.fulfill()
        }
        
        await XCTWaiter().fulfillment(of: [expectation], timeout: 5.0)
        
        Task {
            await dataActivities.run()
            XCTAssertTrue(mockDetectionService.didUpdateFilterSet, "Filter set should be updated")
            expectation.fulfill()
        }
        
        await XCTWaiter().fulfillment(of: [expectation], timeout: 5.0)
    }
}

