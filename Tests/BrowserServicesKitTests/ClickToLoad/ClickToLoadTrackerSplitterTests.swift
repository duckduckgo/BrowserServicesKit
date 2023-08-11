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

    func testShouldNotSplitIfNoCTLTrackersPresent() {
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

    func testShouldSplitTrackerDataIfCTLTrackerPresentInDefaultAction() {
        // given
        let trackers = ["tracker1": ClickToLoadHelper.makeKnownTracker(withName: "example1.com", ownerName: "Example1", defaultAction: .ctlfb)]
        let trackerData = TrackerData(trackers: trackers,
                                      entities: ["Example1": ClickToLoadHelper.makeEntity(withName: "Example1", domains: ["example1.com"])],
                                      domains: ["example1.com": "Example1"],
                                      cnames: ["cname1.com": "example1.com"])
        let rulesList = ContentBlockerRulesList(name: "TrackerDataSet",
                                                trackerData: (trackerData, "etag"),
                                                fallbackTrackerData: (TrackerData(trackers: [:],
                                                                                  entities: [:],
                                                                                  domains: [:],
                                                                                  cnames: nil), "fallback"))

        // when
        let result = ClickToLoadRulesSplitter(rulesList: rulesList).split()

        // then
        XCTAssertNotNil(result)

        XCTAssertEqual(result!.0.trackerData!.tds.trackers.count, 0)
        XCTAssertTrue(result!.0.trackerData!.tds.cnames!.keys.contains("cname1.com"))

        XCTAssertEqual(result!.1.trackerData!.tds.trackers.count, 1)
        XCTAssertTrue(result!.1.trackerData!.tds.entities.keys.contains("Example1"))
        XCTAssertTrue(result!.1.trackerData!.tds.cnames!.keys.contains("cname1.com"))
    }

    func testShouldSplitFallbackTrackerDataIfCTLTrackerPresentInDefaultAction() {
        // given
        let trackers = ["tracker1": ClickToLoadHelper.makeKnownTracker(withName: "example1.com", ownerName: "Example1", defaultAction: .ctlfb)]
        let trackerData = TrackerData(trackers: trackers,
                                      entities: ["Example1": ClickToLoadHelper.makeEntity(withName: "Example1", domains: ["example1.com"])],
                                      domains: ["example1.com": "Example1"],
                                      cnames: ["cname1.com": "example1.com"])
        let rulesList = ContentBlockerRulesList(name: "TrackerDataSet",
                                                trackerData: nil,
                                                fallbackTrackerData: (trackerData, "fallback"))

        // when
        let result = ClickToLoadRulesSplitter(rulesList: rulesList).split()

        // then
        XCTAssertNotNil(result)

        XCTAssertEqual(result!.0.fallbackTrackerData.tds.trackers.count, 0)
        XCTAssertTrue(result!.0.fallbackTrackerData.tds.cnames!.keys.contains("cname1.com"))

        XCTAssertEqual(result!.1.fallbackTrackerData.tds.trackers.count, 1)
        XCTAssertTrue(result!.1.fallbackTrackerData.tds.entities.keys.contains("Example1"))
        XCTAssertTrue(result!.1.fallbackTrackerData.tds.cnames!.keys.contains("cname1.com"))
    }

    func testShouldSplitTrackerDataIfCTLTrackerPresentInRules() {
        // given
        let trackers = ["tracker1": ClickToLoadHelper.makeKnownTracker(withName: "example1.com",
                                                                       ownerName: "Example1",
                                                                       defaultAction: .ignore,
                                                                       rules: [.init(rule: "example1.com/test",
                                                                                     surrogate: nil,
                                                                                     action: .ctlfb,
                                                                                     options: nil,
                                                                                     exceptions: nil)])]
        let trackerData = TrackerData(trackers: trackers,
                                      entities: ["Example1": ClickToLoadHelper.makeEntity(withName: "Example1", domains: ["example1.com"])],
                                      domains: ["example1.com": "Example1"],
                                      cnames: ["cname1.com": "example1.com"])
        let rulesList = ContentBlockerRulesList(name: "TrackerDataSet",
                                                trackerData: (trackerData, "etag"),
                                                fallbackTrackerData: (TrackerData(trackers: [:],
                                                                                  entities: [:],
                                                                                  domains: [:],
                                                                                  cnames: nil), "fallback"))

        // when
        let result = ClickToLoadRulesSplitter(rulesList: rulesList).split()

        // then
        XCTAssertNotNil(result)

        XCTAssertEqual(result!.0.trackerData!.tds.trackers.count, 0)
        XCTAssertTrue(result!.0.trackerData!.tds.cnames!.keys.contains("cname1.com"))

        XCTAssertEqual(result!.1.trackerData!.tds.trackers.count, 1)
        XCTAssertTrue(result!.1.trackerData!.tds.entities.keys.contains("Example1"))
        XCTAssertTrue(result!.1.trackerData!.tds.cnames!.keys.contains("cname1.com"))
    }

    func testShouldSplitFallbackTrackerDataIfCTLTrackerPresentInRules() {
        // given
        let trackers = ["tracker1": ClickToLoadHelper.makeKnownTracker(withName: "example1.com",
                                                                       ownerName: "Example1",
                                                                       defaultAction: .ignore,
                                                                       rules: [.init(rule: "example1.com/test",
                                                                                     surrogate: nil,
                                                                                     action: .ctlfb,
                                                                                     options: nil,
                                                                                     exceptions: nil)])]
        let trackerData = TrackerData(trackers: trackers,
                                      entities: ["Example1": ClickToLoadHelper.makeEntity(withName: "Example1", domains: ["example1.com"])],
                                      domains: ["example1.com": "Example1"],
                                      cnames: ["cname1.com": "example1.com"])
        let rulesList = ContentBlockerRulesList(name: "TrackerDataSet",
                                                trackerData: nil,
                                                fallbackTrackerData: (trackerData, "fallback"))

        // when
        let result = ClickToLoadRulesSplitter(rulesList: rulesList).split()

        // then
        XCTAssertNotNil(result)

        XCTAssertEqual(result!.0.fallbackTrackerData.tds.trackers.count, 0)
        XCTAssertTrue(result!.0.fallbackTrackerData.tds.cnames!.keys.contains("cname1.com"))

        XCTAssertEqual(result!.1.fallbackTrackerData.tds.trackers.count, 1)
        XCTAssertTrue(result!.1.fallbackTrackerData.tds.entities.keys.contains("Example1"))
        XCTAssertTrue(result!.1.fallbackTrackerData.tds.cnames!.keys.contains("cname1.com"))
    }

}
