//
//  File.swift
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

final class ClickToLoadRulesMutatorTests: XCTestCase {

    func testAddingExceptionToNotExistentTrackerShouldNotCauseAnyEffect() {
        // given
        let trackers = [
            "tracker0": ClickToLoadHelper.makeKnownTracker(withName: "example0.com", ownerName: "Example0", defaultAction: .block),
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
        let trackerData = TrackerData(trackers: trackers, entities: [:], domains: [:], cnames: nil)


        // when
        let mutator = ClickToLoadRulesMutator(trackerData: trackerData)
        let mutatedTrackerData = mutator.addExceptions(forDomain: "example.com", for: .all)

        // then
        XCTAssertEqual(trackerData, mutatedTrackerData)
    }

    func testAddingExceptionToTrackerWithBlockActionShouldNotCauseAnyEffect() {
        // given
        let trackers = ["tracker1": ClickToLoadHelper.makeKnownTracker(withName: "example1.com", ownerName: "Example1", defaultAction: .block),
                        "tracker2": ClickToLoadHelper.makeKnownTracker(withName: "example2.com", ownerName: "Example2", defaultAction: .ctlfb),
                        "tracker3": ClickToLoadHelper.makeKnownTracker(withName: "example3.com",
                                                     ownerName: "Example3",
                                                     defaultAction: .block,
                                                     rules: [.init(rule: "example3.com/test",
                                                                   surrogate: nil,
                                                                   action: .block,
                                                                   options: nil,
                                                                   exceptions: nil)])]
        let trackerData = TrackerData(trackers: trackers, entities: [:], domains: [:], cnames: nil)


        // when
        let mutator = ClickToLoadRulesMutator(trackerData: trackerData)
        let mutatedTrackerData = mutator.addExceptions(forDomain: "example1.com", for: .all)

        // then
        XCTAssertEqual(trackerData, mutatedTrackerData)
    }

    func testAddingExceptionWithYTOptionToTrackerWithCTLFBActionShouldNotCauseAnyEffect() {
        // given
        let trackers = ["tracker1": ClickToLoadHelper.makeKnownTracker(withName: "example1.com", ownerName: "Example1", defaultAction: .block),
                        "tracker2": ClickToLoadHelper.makeKnownTracker(withName: "example2.com", ownerName: "Example2", defaultAction: .ctlfb),
                        "tracker3": ClickToLoadHelper.makeKnownTracker(withName: "example3.com",
                                                     ownerName: "Example3",
                                                     defaultAction: .block,
                                                     rules: [.init(rule: "example3.com/test",
                                                                   surrogate: nil,
                                                                   action: .block,
                                                                   options: nil,
                                                                   exceptions: nil)])]
        let trackerData = TrackerData(trackers: trackers, entities: [:], domains: [:], cnames: nil)


        // when
        let mutator = ClickToLoadRulesMutator(trackerData: trackerData)
        let mutatedTrackerData = mutator.addExceptions(forDomain: "example2.com", for: .yt)

        // then
        XCTAssertEqual(trackerData, mutatedTrackerData)
    }

    func testAddingExceptionWithFBOptionToTrackerWithDefaultCTLFBAction() {
        // given
        let trackers = ["tracker1": ClickToLoadHelper.makeKnownTracker(withName: "example1.com", ownerName: "Example1", defaultAction: .block),
                        "tracker2": ClickToLoadHelper.makeKnownTracker(withName: "example2.com", ownerName: "Example2", defaultAction: .ctlfb),
                        "tracker3": ClickToLoadHelper.makeKnownTracker(withName: "example3.com",
                                                     ownerName: "Example3",
                                                     defaultAction: .block,
                                                     rules: [.init(rule: "example3.com/test",
                                                                   surrogate: nil,
                                                                   action: .block,
                                                                   options: nil,
                                                                   exceptions: nil)])]
        let trackerData = TrackerData(trackers: trackers, entities: [:], domains: [:], cnames: nil)


        // when
        let mutator = ClickToLoadRulesMutator(trackerData: trackerData)
        let mutatedTrackerData = mutator.addExceptions(forDomain: "exception.com", for: .fb)

        // then
        XCTAssertNotEqual(trackerData, mutatedTrackerData)
        XCTAssertEqual(mutatedTrackerData.trackers["tracker2.com"]?.rules?.first?.exceptions?.domains, ["exception.com"])
        XCTAssertEqual(mutatedTrackerData.trackers["tracker2.com"]?.rules?.first?.rule, ["example2\\.com(:[0-9]+)?/.*"])
    }

    func testAddingExceptionWithFBOptionToTrackerWithCTLFBActionRule() {
        // given
        let trackers = ["tracker1": ClickToLoadHelper.makeKnownTracker(withName: "example1.com", ownerName: "Example1", defaultAction: .block),
                        "tracker2": ClickToLoadHelper.makeKnownTracker(withName: "example2.com", ownerName: "Example2", defaultAction: .ctlfb),
                        "tracker3": ClickToLoadHelper.makeKnownTracker(withName: "example3.com",
                                                     ownerName: "Example3",
                                                     defaultAction: .block,
                                                     rules: [.init(rule: "example3.com/test",
                                                                   surrogate: nil,
                                                                   action: .ctlfb,
                                                                   options: nil,
                                                                   exceptions: nil)])]
        let trackerData = TrackerData(trackers: trackers, entities: [:], domains: [:], cnames: nil)


        // when
        let mutator = ClickToLoadRulesMutator(trackerData: trackerData)
        let mutatedTrackerData = mutator.addExceptions(forDomain: "exception.com", for: .fb)

        // then
        XCTAssertNotEqual(trackerData, mutatedTrackerData)
        XCTAssertEqual(mutatedTrackerData.trackers["tracker3.com"]?.rules?.first?.exceptions?.domains, ["exception.com"])
        XCTAssertEqual(mutatedTrackerData.trackers["tracker3.com"]?.rules?.first?.rule, ["example3.com"]
    }
                       

}
