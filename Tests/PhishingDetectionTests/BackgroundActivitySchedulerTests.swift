//
//  BackgroundActivitySchedulerTests.swift
//
//
//  Created by Thom on 30/05/2024.
//
import Foundation
import XCTest
@testable import PhishingDetection

class BackgroundActivitySchedulerTests: XCTestCase {
    var scheduler: BackgroundActivityScheduler!
    var activityWasRun = false

    override func setUp() {
        super.setUp()
        scheduler = BackgroundActivityScheduler(interval: 1, identifier: "test")
    }

    override func tearDown() {
        scheduler = nil
        super.tearDown()
    }

    func testStart() {
        let expectation = self.expectation(description: "Activity should run")
        scheduler.start {
            if !self.activityWasRun {
                self.activityWasRun = true
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 2, handler: nil)
        XCTAssertTrue(activityWasRun)
    }

    func testRepeats() {
        let expectation = self.expectation(description: "Activity should repeat")
        var runCount = 0
        scheduler.start {
            runCount += 1
            if runCount == 2 {
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 3, handler: nil)
        XCTAssertEqual(runCount, 2)
    }
}
