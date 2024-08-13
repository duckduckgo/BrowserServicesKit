//
//  BackgroundActivitySchedulerTests.swift
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

class BackgroundActivitySchedulerTests: XCTestCase {
    var scheduler: BackgroundActivityScheduler!
    var activityWasRun = false

    override func tearDown() {
        scheduler = nil
        super.tearDown()
    }

    func testStart() async throws {
        let expectation = self.expectation(description: "Activity should run")
        scheduler = BackgroundActivityScheduler(interval: 1, identifier: "test") {
            if !self.activityWasRun {
                self.activityWasRun = true
                expectation.fulfill()
            }
        }
        await scheduler.start()
        try await fulfillment(of: [expectation], timeout: 2)
        XCTAssertTrue(activityWasRun)
    }

    func testRepeats() async throws {
        let expectation = self.expectation(description: "Activity should repeat")
        var runCount = 0
        scheduler = BackgroundActivityScheduler(interval: 1, identifier: "test") {
            runCount += 1
            if runCount == 2 {
                expectation.fulfill()
            }
        }
        await scheduler.start()
        try await fulfillment(of: [expectation], timeout: 3)
        XCTAssertEqual(runCount, 2)
    }
}
