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
        
        _ = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                       exceptionsSource: mockExceptionsSource,
                                       lastCompiledRulesStore: mockLastCompiledRulesStore,
                                       updateListener: rulesUpdateListener)
        
        wait(for: [exp], timeout: 15.0)
        
        XCTAssertNotNil(mockLastCompiledRulesStore.rules)
        XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.etag, mockRulesSource.trackerData?.etag)
        XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.name, mockRulesSource.rukeListName)
        XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.trackerData, mockRulesSource.trackerData?.tds)
        
        XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.identifier,
                       ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                     tdsEtag: mockRulesSource.trackerData?.etag ?? "\"\"",
                                                     tempListEtag: nil,
                                                     allowListEtag: nil,
                                                     unprotectedSitesHash: nil))
    }
    
    // func last compiled rules == mockRulesSource -> 1 compilation (?)
    // func last compiled rules and no source
    // func last compiled rules == changed config in the meantime, we have to do 2 compilations
    
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
