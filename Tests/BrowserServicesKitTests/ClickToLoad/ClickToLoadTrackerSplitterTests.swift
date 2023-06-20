//
//  ClickToLoadRulesSplitterTests.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
@testable import BrowserServicesKit
@testable import TrackerRadarKit

final class ClickToLoadRulesSplitterTests: XCTestCase {

    func testShouldNotSplitIfNoCTLTrackersPresentInAnyFields() {
        // given
        let trackers = ["tracker1": ClickToLoadHelper.makeKnownTracker(withName: "example1.com", ownerName: "Example1", defaultAction: .block),
                        "tracker2": ClickToLoadHelper.makeKnownTracker(withName: "example2.com", ownerName: "Example2", defaultAction: .ignore),
                        "tracker3": ClickToLoadHelper.makeKnownTracker(withName: "example3.com",
                                                     ownerName: "Example3",
                                                     defaultAction: .block,
                                                     rules: [.init(rule: "example3.com/test",
                                                                   surrogate: nil,
                                                                   action: .block,
                                                                   options: nil,
                                                                   exceptions: nil)])]
        let trackerData = TrackerData(trackers: trackers, entities: [:], domains: [:], cnames: nil)
        let rulesList = ContentBlockerRulesList(name: "TrackerDataSet",
                                                trackerData: (trackerData, "etag"),
                                                fallbackTrackerData: (trackerData, "fallback"))

        // when
        let result = ClickToLoadRulesSplitter(rulesList: rulesList).split()

        // then
        XCTAssertNil(result)
    }

    func testShouldSplitIfCTLTrackersPresentInTrackers() {
        // given
        let trackers = [
            "tracker1": ClickToLoadHelper.makeKnownTracker(withName: "example1.com", ownerName: "Example1", defaultAction: .ctlfb),
            "tracker2": ClickToLoadHelper.makeKnownTracker(withName: "example2.com", ownerName: "Example2", defaultAction: .ctlyt),
            "tracker3": ClickToLoadHelper.makeKnownTracker(withName: "example3.com",
                                         ownerName: "Example3",
                                         defaultAction: .block,
                                         rules: [.init(rule: "example3.com/test",
                                                       surrogate: nil,
                                                       action: .block,
                                                       options: nil,
                                                       exceptions: nil)]),
            "tracker4": ClickToLoadHelper.makeKnownTracker(withName: "example4.com",
                                         ownerName: "Example4",
                                         defaultAction: .ignore,
                                         rules: [.init(rule: "example4.com/test",
                                                       surrogate: nil,
                                                       action: .ctlfb,
                                                       options: nil,
                                                       exceptions: nil)])
        ]
        let trackerData = TrackerData(trackers: trackers,
                                      entities: [
                                        "Example1": ClickToLoadHelper.makeEntity(withName: "Example1", domains: ["example1.com"]),
                                        "Example2": ClickToLoadHelper.makeEntity(withName: "Example2", domains: ["example2.com"]),
                                        "Example3": ClickToLoadHelper.makeEntity(withName: "Example3", domains: ["example3.com"]),
                                        "Example4": ClickToLoadHelper.makeEntity(withName: "Example4", domains: ["example4.com"])
                                                ],
                                      domains: [
                                        "example1.com": "Example1",
                                        "example2.com": "Example2",
                                        "example3.com": "Example3",
                                        "example4.com": "Example4"
                                               ],
                                      cnames: nil)
        let rulesList = ContentBlockerRulesList(name: "TrackerDataSet",
                                                trackerData: (trackerData, "etag"),
                                                fallbackTrackerData: (trackerData, "fallback"))

        // when
        let result = ClickToLoadRulesSplitter(rulesList: rulesList).split()

        // then
        XCTAssertNotNil(result)

        // original list
        XCTAssertEqual(result!.0.trackerData!.tds.trackers.count, 1)
        XCTAssertTrue(result!.0.trackerData!.tds.trackers.keys.contains("tracker3"))
        XCTAssertEqual(result!.0.trackerData!.tds.entities.count, 1)
        XCTAssertTrue(result!.0.trackerData!.tds.entities.keys.contains("Example3"))
        XCTAssertEqual(result!.0.trackerData!.tds.domains.count, 1)
        XCTAssertTrue(result!.0.trackerData!.tds.domains.keys.contains("example3.com"))
        XCTAssertEqual(result!.0.fallbackTrackerData.tds.trackers.count, 1)
        XCTAssertEqual(result!.0.fallbackTrackerData.tds.trackers.first?.key, "tracker3")
        XCTAssertEqual(result!.0.fallbackTrackerData.tds.entities.count, 1)
        XCTAssertTrue(result!.0.fallbackTrackerData.tds.entities.keys.contains("Example3"))
        XCTAssertEqual(result!.0.fallbackTrackerData.tds.domains.count, 1)
        XCTAssertTrue(result!.0.fallbackTrackerData.tds.domains.keys.contains("example3.com"))

        // ctl list
        XCTAssertEqual(result!.1.trackerData!.tds.trackers.count, 3)
        XCTAssertTrue(result!.1.trackerData!.tds.trackers.keys.contains("tracker1"))
        XCTAssertTrue(result!.1.trackerData!.tds.trackers.keys.contains("tracker2"))
        XCTAssertTrue(result!.1.trackerData!.tds.trackers.keys.contains("tracker4"))
        XCTAssertEqual(result!.1.trackerData!.tds.entities.count, 3)
        XCTAssertTrue(result!.1.trackerData!.tds.entities.keys.contains("Example1"))
        XCTAssertTrue(result!.1.trackerData!.tds.entities.keys.contains("Example2"))
        XCTAssertTrue(result!.1.trackerData!.tds.entities.keys.contains("Example4"))
        XCTAssertEqual(result!.1.trackerData!.tds.domains.count, 3)
        XCTAssertTrue(result!.1.trackerData!.tds.domains.keys.contains("example1.com"))
        XCTAssertTrue(result!.1.trackerData!.tds.domains.keys.contains("example2.com"))
        XCTAssertTrue(result!.1.trackerData!.tds.domains.keys.contains("example4.com"))
        XCTAssertEqual(result!.1.fallbackTrackerData.tds.trackers.count, 3)
        XCTAssertTrue(result!.1.fallbackTrackerData.tds.trackers.keys.contains("tracker1"))
        XCTAssertTrue(result!.1.fallbackTrackerData.tds.trackers.keys.contains("tracker2"))
        XCTAssertTrue(result!.1.fallbackTrackerData.tds.trackers.keys.contains("tracker4"))
        XCTAssertEqual(result!.1.fallbackTrackerData.tds.entities.count, 3)
        XCTAssertTrue(result!.1.fallbackTrackerData.tds.entities.keys.contains("Example1"))
        XCTAssertTrue(result!.1.fallbackTrackerData.tds.entities.keys.contains("Example2"))
        XCTAssertTrue(result!.1.fallbackTrackerData.tds.entities.keys.contains("Example4"))
        XCTAssertEqual(result!.1.fallbackTrackerData.tds.domains.count, 3)
        XCTAssertTrue(result!.1.fallbackTrackerData.tds.domains.keys.contains("example1.com"))
        XCTAssertTrue(result!.1.fallbackTrackerData.tds.domains.keys.contains("example2.com"))
        XCTAssertTrue(result!.1.fallbackTrackerData.tds.domains.keys.contains("example4.com"))
    }

}
