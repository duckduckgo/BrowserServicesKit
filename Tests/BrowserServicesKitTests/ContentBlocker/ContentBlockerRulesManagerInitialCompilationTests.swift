//
//  ContentBlockerRulesManagerTests.swift
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

import Foundation
import TrackerRadarKit
import BrowserServicesKit
import WebKit
import XCTest

final class CountedFulfillmentTestExpectation: XCTestExpectation {
    private(set) var currentFulfillmentCount: Int = 0

    override func fulfill() {
        currentFulfillmentCount += 1
        super.fulfill()
    }
}

// swiftlint:disable line_length
final class ContentBlockerRulesManagerInitialCompilationTests: XCTestCase {
    
    private static let fakeEmbeddedDataSet = ContentBlockerRulesManagerTests.makeDataSet(tds: ContentBlockerRulesManagerTests.validRules, etag: "\"\(UUID().uuidString)\"")
    private let rulesUpdateListener = RulesUpdateListener()
    
    func testSuccessfulCompilationStoresLastCompiledRules() {
        
        let mockRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: ContentBlockerRulesManagerTests.makeDataSet(tds: ContentBlockerRulesManagerTests.validRules,
                                                                                                                                etag: ContentBlockerRulesManagerTests.makeEtag()),
                                                                       embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        let mockLastCompiledRulesStore = MockLastCompiledRulesStore()
        
        let exp = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            exp.fulfill()
        }
        
        let cbrm = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                              exceptionsSource: mockExceptionsSource,
                                              lastCompiledRulesStore: mockLastCompiledRulesStore,
                                              updateListener: rulesUpdateListener)
        
        wait(for: [exp], timeout: 15.0)
        
        XCTAssertNotNil(mockLastCompiledRulesStore.rules)
        XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.etag, mockRulesSource.trackerData?.etag)
        XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.name, mockRulesSource.rukeListName)
        XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.trackerData, mockRulesSource.trackerData?.tds)
        XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.identifier, cbrm.currentRules.first?.identifier)
    }
        
    func testInitialCompilation_WhenNoChangesToTDS_ShouldUpdateRulesTwice() {
        
        let mockRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: ContentBlockerRulesManagerTests.makeDataSet(tds: ContentBlockerRulesManagerTests.validRules,
                                                                                                                                etag: ContentBlockerRulesManagerTests.makeEtag()),
                                                                       embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        let mockLastCompiledRulesStore = MockLastCompiledRulesStore()
        let identifier = ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                       tdsEtag: mockRulesSource.trackerData?.etag ?? "\"\"",
                                                       tempListId: nil,
                                                       allowListId: nil,
                                                       unprotectedSitesHash: nil)
        let cachedRules = MockLastCompiledRules(name: mockRulesSource.rukeListName,
                                                trackerData: mockRulesSource.trackerData!.tds,
                                                etag: mockRulesSource.trackerData!.etag,
                                                identifier: identifier)

        mockLastCompiledRulesStore.rules = [cachedRules]
        
        // simulate the rules have been compiled in the past so the WKContentRuleListStore contains it
        _ = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                       exceptionsSource: mockExceptionsSource,
                                       updateListener: rulesUpdateListener)

        let exp = CountedFulfillmentTestExpectation(description: "Rules Compiled")
        exp.expectedFulfillmentCount = 3
        rulesUpdateListener.onRulesUpdated = { rules in
            exp.fulfill()
            if exp.currentFulfillmentCount == 1 { // finished compilation after first installation
                _ = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                               exceptionsSource: mockExceptionsSource,
                                               lastCompiledRulesStore: mockLastCompiledRulesStore,
                                               updateListener: self.rulesUpdateListener)
            }
            assertRules(rules)
        }

        wait(for: [exp], timeout: 15.0)
        
        func assertRules(_ rules: [ContentBlockerRulesManager.Rules]) {
            guard let rules = rules.first else { XCTFail(); return }
            XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.etag, rules.etag)
            XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.name, rules.name)
            XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.trackerData, rules.trackerData)
            XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.identifier, rules.identifier)
        }
    }
    
    // swiftlint:disable:next function_body_length
    func testInitialCompilation_WhenThereAreChangesToTDS_ShouldBuildRulesUsingLastCompiledRulesAndScheduleRecompilationWithNewSource() {
        
        let oldEtag = ContentBlockerRulesManagerTests.makeEtag()
        let mockRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: ContentBlockerRulesManagerTests.makeDataSet(tds: ContentBlockerRulesManagerTests.validRules,
                                                                                                                                etag: oldEtag),
                                                                       embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let updatedEtag = ContentBlockerRulesManagerTests.makeEtag()
        let mockUpdatedRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: ContentBlockerRulesManagerTests.makeDataSet(tds: ContentBlockerRulesManagerTests.validRules,
                                                                                                                                       etag: updatedEtag),
                                                                              embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        let mockLastCompiledRulesStore = MockLastCompiledRulesStore()
        let oldIdentifier = ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                          tdsEtag: mockRulesSource.trackerData?.etag ?? "\"\"",
                                                          tempListId: nil,
                                                          allowListId: nil,
                                                          unprotectedSitesHash: nil)
        let newIdentifier = ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                          tdsEtag: mockUpdatedRulesSource.trackerData?.etag ?? "\"\"",
                                                          tempListId: nil,
                                                          allowListId: nil,
                                                          unprotectedSitesHash: nil)
        let cachedRules = MockLastCompiledRules(name: mockRulesSource.rukeListName,
                                                trackerData: mockRulesSource.trackerData!.tds,
                                                etag: mockRulesSource.trackerData!.etag,
                                                identifier: oldIdentifier)
        
        mockLastCompiledRulesStore.rules = [cachedRules]
        
        // simulate the rules have been compiled in the past so the WKContentRuleListStore contains it
        _ = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                       exceptionsSource: mockExceptionsSource,
                                       updateListener: rulesUpdateListener)

        let exp = CountedFulfillmentTestExpectation(description: "Rules Compiled")
        exp.expectedFulfillmentCount = 3
        rulesUpdateListener.onRulesUpdated = { rules in
            exp.fulfill()
            if exp.currentFulfillmentCount == 1 { // finished compilation after first installation
                _ = ContentBlockerRulesManager(rulesSource: mockUpdatedRulesSource,
                                               exceptionsSource: mockExceptionsSource,
                                               lastCompiledRulesStore: mockLastCompiledRulesStore,
                                               updateListener: self.rulesUpdateListener)
            } else if exp.currentFulfillmentCount == 2 { // finished compilation after cold start (using last compiled rules)
                XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.etag, oldEtag)
                XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.name, mockRulesSource.rukeListName)
                XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.trackerData, mockRulesSource.trackerData?.tds)
                XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.identifier, oldIdentifier)
            } else if exp.currentFulfillmentCount == 3 { // finished recompilation of rules due to changed tds
                XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.etag, updatedEtag)
                XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.name, mockRulesSource.rukeListName)
                XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.trackerData, mockRulesSource.trackerData?.tds)
                XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.identifier, newIdentifier)
            }
        }

        wait(for: [exp], timeout: 15.0)
    }
    
    struct MockLastCompiledRules: LastCompiledRules {
        
        var name: String
        var trackerData: TrackerData
        var etag: String
        var identifier: ContentBlockerRulesIdentifier
    
    }
    
    final class MockLastCompiledRulesStore: LastCompiledRulesStore {
        
        var rules: [LastCompiledRules] = []
        
        func update(with contentBlockerRules: [ContentBlockerRulesManager.Rules]) {
            rules = contentBlockerRules.map { rules in
                MockLastCompiledRules(name: rules.name,
                                      trackerData: rules.trackerData,
                                      etag: rules.etag,
                                      identifier: rules.identifier)
            }
        }
        
    }
    
}
