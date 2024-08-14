//
//  PhishingDetectionDataActivitiesTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
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
