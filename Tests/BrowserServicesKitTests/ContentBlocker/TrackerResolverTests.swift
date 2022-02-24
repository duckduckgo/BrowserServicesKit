//
//  TrackerResolverTests.swift
//  DuckDuckGo
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import XCTest
import TrackerRadarKit
@testable import BrowserServicesKit

class TrackerResolverTests: XCTestCase {

    func testWhenOptionsAreEmptyThenNothingMatches() {

        let rule = KnownTracker.Rule.Matching(domains: [], types: [])

        let urlOne = URL(string: "https://www.one.com")!

        XCTAssertFalse(TrackerResolver.isMatching(rule,
                                                 host: urlOne.host!,
                                                 resourceType: "image"))
    }

    func testWhenDomainsAreRequiredThenTypesDoNotMatter() {

        let rule = KnownTracker.Rule.Matching(domains: ["one.com", "two.com"], types: nil)

        let urlOne = URL(string: "https://www.one.com")!
        let urlTwo = URL(string: "https://two.com")!
        let urlThree = URL(string: "https://www.three.com")!

        XCTAssertTrue(TrackerResolver.isMatching(rule,
                                                 host: urlOne.host!,
                                                 resourceType: "image"))
        XCTAssertTrue(TrackerResolver.isMatching(rule,
                                                 host: urlTwo.host!,
                                                 resourceType: "image"))
        XCTAssertFalse(TrackerResolver.isMatching(rule,
                                                  host: urlThree.host!,
                                                  resourceType: "image"))
    }

    func testWhenTypesAreRequiredThenDomainsDoNotMatter() {

        let rule = KnownTracker.Rule.Matching(domains: [], types: ["image", "script"])

        let urlOne = URL(string: "https://www.one.com")!
        let urlTwo = URL(string: "https://two.com")!
        let urlThree = URL(string: "https://www.three.com")!

        XCTAssertTrue(TrackerResolver.isMatching(rule,
                                                 host: urlOne.host!,
                                                 resourceType: "image"))
        XCTAssertTrue(TrackerResolver.isMatching(rule,
                                                 host: urlTwo.host!,
                                                 resourceType: "script"))
        XCTAssertFalse(TrackerResolver.isMatching(rule,
                                                 host: urlThree.host!,
                                                 resourceType: "link"))
        XCTAssertTrue(TrackerResolver.isMatching(rule,
                                                 host: urlThree.host!,
                                                 resourceType: "image"))
    }

    func testWhenTypesAndDomainsAreRequiredThenItIsAnAndRequirement() {

        let rule = KnownTracker.Rule.Matching(domains: ["one.com", "two.com"], types: ["image", "script"])

        let urlOne = URL(string: "https://www.one.com")!
        let urlTwo = URL(string: "https://two.com")!
        let urlThree = URL(string: "https://www.three.com")!

        XCTAssertTrue(TrackerResolver.isMatching(rule,
                                                 host: urlOne.host!,
                                                 resourceType: "image"))
        XCTAssertFalse(TrackerResolver.isMatching(rule,
                                                 host: urlOne.host!,
                                                 resourceType: "link"))
        XCTAssertTrue(TrackerResolver.isMatching(rule,
                                                 host: urlOne.host!,
                                                 resourceType: "script"))

        XCTAssertTrue(TrackerResolver.isMatching(rule,
                                                 host: urlTwo.host!,
                                                 resourceType: "script"))
        XCTAssertFalse(TrackerResolver.isMatching(rule,
                                                 host: urlTwo.host!,
                                                 resourceType: "link"))

        XCTAssertFalse(TrackerResolver.isMatching(rule,
                                                 host: urlThree.host!,
                                                 resourceType: "link"))
        XCTAssertFalse(TrackerResolver.isMatching(rule,
                                                 host: urlThree.host!,
                                                 resourceType: "image"))
    }
    
    func testWhenTrackerIsDetectedThenItIsReported() {
        
        let tracker = KnownTracker(domain: "tracker.com",
                                   defaultAction: .block,
                                   owner: KnownTracker.Owner(name: "Tracker Inc",
                                                             displayName: "Tracker Inc company"),
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: nil,
                                   rules: nil)
        
        let tds = TrackerData(trackers: ["tracker.com" : tracker],
                              entities: ["Tracker Inc": Entity(displayName: "Trackr Inc company",
                                                               domains: ["tracker.com"],
                                                               prevalence: 0.1)],
                              domains: ["tracker.com": "Tracker Inc"],
                              cnames: [:])
        
        let resolver = TrackerResolver(tds: tds, unprotectedSites: [], tempList: [])
        
        let result = resolver.trackerFromUrl("https://tracker.com/img/1.png", pageUrlString: "example.com", resourceType: "image", potentiallyBlocked: true)
    
        XCTAssertNotNil(result)
        XCTAssert(result?.blocked ?? false)
        XCTAssertEqual(result?.knownTracker, tracker)
    }
    
    func testWhenTrackerIsOnAssociatedPageThenItIsNotBlocked() {
        
        let tracker = KnownTracker(domain: "tracker.com",
                                   defaultAction: .block,
                                   owner: KnownTracker.Owner(name: "Tracker Inc",
                                                             displayName: "Tracker Inc company"),
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: nil,
                                   rules: nil)
        
        let tds = TrackerData(trackers: ["tracker.com" : tracker],
                              entities: ["Tracker Inc": Entity(displayName: "Tracker Inc company",
                                                               domains: ["tracker.com", "example.com"],
                                                               prevalence: 0.1)],
                              domains: ["tracker.com": "Tracker Inc",
                                        "example.com": "Tracker Inc"],
                              cnames: [:])
        
        let resolver = TrackerResolver(tds: tds, unprotectedSites: [], tempList: [])
        
        let result = resolver.trackerFromUrl("https://tracker.com/img/1.png", pageUrlString: "https://example.com", resourceType: "image", potentiallyBlocked: true)
    
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.blocked)
    }
    
    func testWhenTrackerIsACnameThenItIsReportedAsSuch() {
        
        let tracker = KnownTracker(domain: "tracker.com",
                                   defaultAction: .block,
                                   owner: KnownTracker.Owner(name: "Tracker Inc",
                                                             displayName: "Tracker Inc company"),
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: nil,
                                   rules: nil)
        
        let tds = TrackerData(trackers: ["tracker.com" : tracker],
                              entities: ["Tracker Inc": Entity(displayName: "Tracker Inc company",
                                                               domains: ["tracker.com"],
                                                               prevalence: 0.1)],
                              domains: ["tracker.com": "Tracker Inc"],
                              cnames: ["cnamed.com": "tracker.com"])
        
        let resolver = TrackerResolver(tds: tds, unprotectedSites: [], tempList: [])
        
        let result = resolver.trackerFromUrl("https://cnamed.com/img/1.png", pageUrlString: "https://example.com", resourceType: "image", potentiallyBlocked: true)
    
        XCTAssertNotNil(result)
        XCTAssert(result?.blocked ?? false)
        XCTAssertEqual(result?.knownTracker, tracker)
    }
    
    func testWhenTrackerIsACnameForAnotherTrackerThenOriginalOneIsReturned() {
        
        let tracker = KnownTracker(domain: "tracker.com",
                                   defaultAction: .block,
                                   owner: KnownTracker.Owner(name: "Tracker Inc",
                                                             displayName: "Tracker Inc company"),
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: nil,
                                   rules: nil)
        
        let another = KnownTracker(domain: "another.com",
                                   defaultAction: .block,
                                   owner: KnownTracker.Owner(name: "Another Inc",
                                                             displayName: "Another Inc company"),
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: nil,
                                   rules: nil)
        
        let tds = TrackerData(trackers: ["tracker.com" : tracker,
                                         "another.com" : another],
                              entities: ["Tracker Inc": Entity(displayName: "Tracker Inc company",
                                                               domains: ["tracker.com"],
                                                               prevalence: 0.1),
                                         "Another Inc": Entity(displayName: "Another Inc company",
                                                                          domains: ["another.com"],
                                                                          prevalence: 0.1)],
                              domains: ["tracker.com": "Tracker Inc",
                                        "another.com": "Another Inc."],
                              cnames: ["sub.another.com": "tracker.com"])
        
        let resolver = TrackerResolver(tds: tds, unprotectedSites: [], tempList: [])
        
        let result = resolver.trackerFromUrl("https://sub.another.com/img/1.png", pageUrlString: "https://example.com", resourceType: "image", potentiallyBlocked: true)
    
        XCTAssertNotNil(result)
        XCTAssert(result?.blocked ?? false)
        XCTAssertEqual(result?.knownTracker, another)
    }
}
