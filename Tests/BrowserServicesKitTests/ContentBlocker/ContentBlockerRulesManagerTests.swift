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

import XCTest
import TrackerRadarKit
import BrowserServicesKit

// swiftlint:disable file_length

class ContentBlockerRulesManagerTests: XCTestCase {
    
    static let validRules = """
    {
      "trackers": {
        "notreal.io": {
          "domain": "notreal.io",
          "default": "block",
          "owner": {
            "name": "CleverDATA LLC",
            "displayName": "CleverDATA",
            "privacyPolicy": "https://hermann.ai/privacy-en",
            "url": "http://hermann.ai"
          },
          "source": [
            "DDG"
          ],
          "prevalence": 0.002,
          "fingerprinting": 0,
          "cookies": 0.002,
          "performance": {
            "time": 1,
            "size": 1,
            "cpu": 1,
            "cache": 3
          },
          "categories": [
            "Ad Motivated Tracking",
            "Advertising",
            "Analytics",
            "Third-Party Analytics Marketing"
          ]
        }
      },
      "entities": {
        "Not Real": {
          "domains": [
            "notreal.io"
          ],
          "displayName": "Not Real",
          "prevalence": 0.666
        }
      },
      "domains": {
        "notreal.io": "Not Real"
      }
    }
    """
    
    static let invalidRules = """
    {
      "trackers": {
        "notreal.io": {
          "domain": "this is broken",
          "default": "block",
          "owner": {
            "name": "CleverDATA LLC",
            "displayName": "CleverDATA",
            "privacyPolicy": "https://hermann.ai/privacy-en",
            "url": "test test"
          },
          "source": [
            "DDG"
          ],
          "prevalence": 0.002,
          "fingerprinting": 0,
          "cookies": 0.002,
          "performance": {
            "time": 1,
            "size": 1,
            "cpu": 1,
            "cache": 3
          },
          "categories": [
            "Ad Motivated Tracking",
            "Advertising",
            "Analytics",
            "Third-Party Analytics Marketing"
          ],
          "rules": [
            {
              "rule": "something",
              "exceptions": {
                "domains": [
                  "example.com",
                   "Broken Ltd."
                ]
              }
            }
          ]
        }
      },
      "entities": {
        "Not Real": {
          "domains": [
            "example.com",
            "Broken Ltd.",
            "example.com"
          ],
          "properties": [
            "broken Ltd.",
            "example.net"
          ],
          "displayName": "Not Real",
          "prevalence": 0.666
        }
      },
      "domains": {
        "exampleö.com": "Example",
        "Broken Ltd.": "Not Real",
        "TEsT~~.com": "Example",
        "😉.com": "T"
      }
    }
    """
    
    let validTempSites = ["example.com"]
    let invalidTempSites = ["This is not valid.. ."]

    let validAllowList = [TrackerException(rule: "tracker.com/", matching: .all)]
    let invalidAllowList = [TrackerException(rule: "tracker.com/", matching: .domains(["broken site Ltd. . 😉.com"]))]
    
    static var fakeEmbeddedDataSet: TrackerDataManager.DataSet!
    
    override class func setUp() {
        super.setUp()
        
        fakeEmbeddedDataSet = makeDataSet(tds: validRules, etag: "\"\(UUID().uuidString)\"")
    }
    
    static func makeDataSet(tds: String) -> TrackerDataManager.DataSet {
        return makeDataSet(tds: tds, etag: makeEtag())
    }
    
    static func makeDataSet(tds: String, etag: String) -> TrackerDataManager.DataSet {
        let data = tds.data(using: .utf8)!
        let decoded = try? JSONDecoder().decode(TrackerData.self, from: data)
        return (decoded!, etag)
    }
    
    static func makeEtag() -> String {
        return "\"\(UUID().uuidString)\""
    }
    
}

final class RulesUpdateListener: ContentBlockerRulesUpdating {

    var onRulesUpdated: ([String: ContentBlockerRulesIdentifier.Difference]) -> Void = { _ in }

    func rulesManager(_ manager: ContentBlockerRulesManager,
                      didUpdateRules: [ContentBlockerRulesManager.Rules],
                      changes: [String: ContentBlockerRulesIdentifier.Difference],
                      completionTokens: [ContentBlockerRulesManager.CompletionToken]) {
        onRulesUpdated(changes)
    }
}

// swiftlint:disable type_body_length
class ContentBlockerRulesManagerLoadingTests: ContentBlockerRulesManagerTests {

    private let rulesUpdateListener = RulesUpdateListener()
    
    func test_ValidTDS_NoTempList_NoAllowList_NoUnprotectedSites() {
                
        let mockRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: (Self.fakeEmbeddedDataSet.tds, Self.makeEtag()),
                                                                       embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        XCTAssertNotEqual(mockRulesSource.contentBlockerRulesLists.first?.trackerData?.etag, mockRulesSource.contentBlockerRulesLists.first?.fallbackTrackerData.etag)

        let exp = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            exp.fulfill()
        }

        let cbrm = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                              exceptionsSource: mockExceptionsSource,
                                              updateListener: rulesUpdateListener,
                                              logger: .disabled)

        wait(for: [exp], timeout: 15.0)
        
        XCTAssertNotNil(cbrm.currentRules)
        XCTAssertEqual(cbrm.currentRules.first?.etag, mockRulesSource.trackerData?.etag)

        XCTAssertEqual(cbrm.currentRules.first?.identifier,
                       ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                     tdsEtag: mockRulesSource.trackerData?.etag ?? "",
                                                     tempListEtag: nil,
                                                     allowListEtag: nil,
                                                     unprotectedSitesHash: nil))
    }
    
    func test_InvalidTDS_NoTempList_NoAllowList_NoUnprotectedSites() {

        let mockRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: Self.makeDataSet(tds: Self.invalidRules, etag: Self.makeEtag()),
                                                                       embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
                                                       
        XCTAssertNotEqual(mockRulesSource.trackerData?.etag, mockRulesSource.embeddedTrackerData.etag)
        
        let exp = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            exp.fulfill()
        }

        let cbrm = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                              exceptionsSource: mockExceptionsSource,
                                              updateListener: rulesUpdateListener,
                                              logger: .disabled)

        wait(for: [exp], timeout: 15.0)
        
        XCTAssertNotNil(cbrm.currentRules)
        XCTAssertEqual(cbrm.currentRules.first?.etag, mockRulesSource.embeddedTrackerData.etag)

        XCTAssertEqual(cbrm.currentRules.first?.identifier,
                       ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                     tdsEtag: mockRulesSource.embeddedTrackerData.etag,
                                                     tempListEtag: nil,
                                                     allowListEtag: nil,
                                                     unprotectedSitesHash: nil))
    }
    
    func test_ValidTDS_ValidTempList_NoAllowList_NoUnprotectedSites() {

        let mockRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: Self.makeDataSet(tds: Self.validRules, etag: Self.makeEtag()),
                                                                       embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        mockExceptionsSource.tempListEtag = Self.makeEtag()
        mockExceptionsSource.tempList = validTempSites
        
        XCTAssertNotEqual(mockRulesSource.trackerData?.etag, mockRulesSource.embeddedTrackerData.etag)
        
        let exp = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            exp.fulfill()
        }

        let cbrm = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                              exceptionsSource: mockExceptionsSource,
                                              updateListener: rulesUpdateListener,
                                              logger: .disabled)

        wait(for: [exp], timeout: 15.0)
        
        XCTAssertNotNil(cbrm.currentRules)
        XCTAssertNotNil(cbrm.currentRules.first?.etag)
        XCTAssertEqual(cbrm.currentRules.first?.etag, mockRulesSource.trackerData?.etag)

        XCTAssertEqual(cbrm.currentRules.first?.identifier,
                       ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                     tdsEtag: mockRulesSource.trackerData?.etag ?? "",
                                                     tempListEtag: mockExceptionsSource.tempListEtag,
                                                     allowListEtag: nil,
                                                     unprotectedSitesHash: nil))
    }
    
    func test_InvalidTDS_ValidTempList_NoAllowList_NoUnprotectedSites() {

        let mockRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: Self.makeDataSet(tds: Self.invalidRules, etag: Self.makeEtag()),
                                                                       embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        mockExceptionsSource.tempListEtag = Self.makeEtag()
        mockExceptionsSource.tempList = validTempSites
        
        XCTAssertNotEqual(mockRulesSource.trackerData?.etag, mockRulesSource.embeddedTrackerData.etag)
        
        let exp = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            exp.fulfill()
        }

        let cbrm = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                              exceptionsSource: mockExceptionsSource,
                                              updateListener: rulesUpdateListener,
                                              logger: .disabled)

        wait(for: [exp], timeout: 15.0)
        
        XCTAssertNotNil(cbrm.currentRules.first?.etag)
        
        XCTAssertNotNil(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.tdsIdentifier)
        XCTAssertEqual(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.tdsIdentifier, mockRulesSource.trackerData?.etag)
        
        XCTAssertEqual(cbrm.currentRules.first?.etag, mockRulesSource.embeddedTrackerData.etag)

        XCTAssertEqual(cbrm.currentRules.first?.identifier,
                       ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                     tdsEtag: mockRulesSource.embeddedTrackerData.etag,
                                                     tempListEtag: mockExceptionsSource.tempListEtag,
                                                     allowListEtag: nil,
                                                     unprotectedSitesHash: nil))
    }
    
    func test_ValidTDS_InvalidTempList_NoAllowList_NoUnprotectedSites() {
        
        let mockRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: Self.makeDataSet(tds: Self.validRules, etag: Self.makeEtag()),
                                                                       embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        mockExceptionsSource.tempListEtag = Self.makeEtag()
        mockExceptionsSource.tempList = invalidTempSites
        
        XCTAssertNotEqual(mockRulesSource.trackerData?.etag, mockRulesSource.embeddedTrackerData.etag)
        
        let exp = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            exp.fulfill()
        }

        let cbrm = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                              exceptionsSource: mockExceptionsSource,
                                              updateListener: rulesUpdateListener,
                                              logger: .disabled)

        wait(for: [exp], timeout: 15.0)
        
        XCTAssertNotNil(cbrm.currentRules.first?.etag)
        XCTAssertEqual(cbrm.currentRules.first?.etag, mockRulesSource.embeddedTrackerData.etag)
        
        // TDS is also marked as invalid to simplify flow
        XCTAssertNotNil(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.tdsIdentifier)
        XCTAssertEqual(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.tdsIdentifier, mockRulesSource.trackerData?.etag)
        
        XCTAssertNotNil(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.tempListIdentifier)
        XCTAssertEqual(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.tempListIdentifier, mockExceptionsSource.tempListEtag)

        XCTAssertEqual(cbrm.currentRules.first?.identifier,
                       ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                     tdsEtag: mockRulesSource.embeddedTrackerData.etag,
                                                     tempListEtag: nil,
                                                     allowListEtag: nil,
                                                     unprotectedSitesHash: nil))
    }
    
    func test_ValidTDS_ValidTempList_NoAllowList_ValidUnprotectedSites() {
        
        let mockRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: Self.makeDataSet(tds: Self.validRules, etag: Self.makeEtag()),
                                                                       embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        mockExceptionsSource.tempListEtag = Self.makeEtag()
        mockExceptionsSource.tempList = validTempSites
        mockExceptionsSource.unprotectedSites = ["example.com"]
        
        XCTAssertNotEqual(mockRulesSource.trackerData?.etag, mockRulesSource.embeddedTrackerData.etag)
        
        let exp = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            exp.fulfill()
        }

        let cbrm = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                              exceptionsSource: mockExceptionsSource,
                                              updateListener: rulesUpdateListener,
                                              logger: .disabled)

        wait(for: [exp], timeout: 15.0)
        
        XCTAssertNotNil(cbrm.currentRules.first?.etag)
        XCTAssertEqual(cbrm.currentRules.first?.etag, mockRulesSource.trackerData?.etag)
        
        XCTAssertNil(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.tdsIdentifier)
        XCTAssertNil(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.tempListIdentifier)
        XCTAssertNil(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.unprotectedSitesIdentifier)
        
        XCTAssertEqual(cbrm.currentRules.first?.identifier,
                       ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                     tdsEtag: mockRulesSource.trackerData?.etag ?? "\"\"",
                                                     tempListEtag: mockExceptionsSource.tempListEtag,
                                                     allowListEtag: nil,
                                                     unprotectedSitesHash: mockExceptionsSource.unprotectedSitesHash))
    }

    func test_ValidTDS_ValidTempList_ValidAllowList_ValidUnprotectedSites() {
        
        let mockRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: Self.makeDataSet(tds: Self.validRules, etag: Self.makeEtag()),
                                                                       embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        mockExceptionsSource.tempListEtag = Self.makeEtag()
        mockExceptionsSource.tempList = validTempSites
        mockExceptionsSource.allowListEtag = Self.makeEtag()
        mockExceptionsSource.allowList = validAllowList
        mockExceptionsSource.unprotectedSites = ["example.com"]

        XCTAssertNotEqual(mockRulesSource.trackerData?.etag, mockRulesSource.embeddedTrackerData.etag)

        let exp = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            exp.fulfill()
        }

        let cbrm = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                              exceptionsSource: mockExceptionsSource,
                                              updateListener: rulesUpdateListener,
                                              logger: .disabled)

        wait(for: [exp], timeout: 15.0)

        XCTAssertNotNil(cbrm.currentRules)
        XCTAssertNotNil(cbrm.currentRules.first?.etag)
        XCTAssertEqual(cbrm.currentRules.first?.etag, mockRulesSource.trackerData?.etag)

        XCTAssertNil(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.tdsIdentifier)
        XCTAssertNil(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.tempListIdentifier)
        XCTAssertNil(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.allowListIdentifier)
        XCTAssertNil(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.unprotectedSitesIdentifier)

        XCTAssertEqual(cbrm.currentRules.first?.identifier,
                       ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                     tdsEtag: mockRulesSource.trackerData?.etag ?? "\"\"",
                                                     tempListEtag: mockExceptionsSource.tempListEtag,
                                                     allowListEtag: mockExceptionsSource.allowListEtag,
                                                     unprotectedSitesHash: mockExceptionsSource.unprotectedSitesHash))
    }

    func test_ValidTDS_ValidTempList_InvalidAllowList_ValidUnprotectedSites() {

        let mockRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: Self.makeDataSet(tds: Self.validRules, etag: Self.makeEtag()),
                                                                       embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        mockExceptionsSource.tempListEtag = Self.makeEtag()
        mockExceptionsSource.tempList = validTempSites
        mockExceptionsSource.allowListEtag = Self.makeEtag()
        mockExceptionsSource.allowList = invalidAllowList
        mockExceptionsSource.unprotectedSites = ["example.com"]

        XCTAssertNotEqual(mockRulesSource.trackerData?.etag, mockRulesSource.embeddedTrackerData.etag)

        let exp = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            exp.fulfill()
        }

        let cbrm = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                              exceptionsSource: mockExceptionsSource,
                                              updateListener: rulesUpdateListener,
                                              logger: .disabled)

        wait(for: [exp], timeout: 15.0)

        XCTAssertNotNil(cbrm.currentRules.first?.etag)
        XCTAssertEqual(cbrm.currentRules.first?.etag, mockRulesSource.embeddedTrackerData.etag)

        // TDS is also marked as invalid to simplify flow
        XCTAssertNotNil(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.tdsIdentifier)
        XCTAssertEqual(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.tdsIdentifier, mockRulesSource.trackerData?.etag)

        XCTAssertNotNil(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.allowListIdentifier)
        XCTAssertEqual(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.allowListIdentifier, mockExceptionsSource.allowListEtag)

        XCTAssertNil(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.unprotectedSitesIdentifier)

        XCTAssertEqual(cbrm.currentRules.first?.identifier,
                       ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                     tdsEtag: mockRulesSource.embeddedTrackerData.etag,
                                                     tempListEtag: nil,
                                                     allowListEtag: nil,
                                                     unprotectedSitesHash: mockExceptionsSource.unprotectedSitesHash))
    }
    
    func test_ValidTDS_ValidTempList_ValidAllowList_BrokenUnprotectedSites() {
        
        let mockRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: Self.makeDataSet(tds: Self.validRules, etag: Self.makeEtag()),
                                                                       embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        mockExceptionsSource.tempListEtag = Self.makeEtag()
        mockExceptionsSource.tempList = validTempSites
        mockExceptionsSource.allowListEtag = Self.makeEtag()
        mockExceptionsSource.allowList = validAllowList
        mockExceptionsSource.unprotectedSites = ["broken site Ltd. . 😉.com"]
        
        XCTAssertNotEqual(mockRulesSource.trackerData?.etag, mockRulesSource.embeddedTrackerData.etag)
        
        let exp = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            exp.fulfill()
        }

        let cbrm = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                              exceptionsSource: mockExceptionsSource,
                                              updateListener: rulesUpdateListener,
                                              logger: .disabled)

        wait(for: [exp], timeout: 15.0)
        
        XCTAssertNotNil(cbrm.currentRules.first?.etag)
        XCTAssertEqual(cbrm.currentRules.first?.etag, mockRulesSource.embeddedTrackerData.etag)
        
        // TDS is also marked as invalid to simplify flow
        XCTAssertNotNil(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.tdsIdentifier)
        XCTAssertEqual(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.tdsIdentifier, mockRulesSource.trackerData?.etag)
        
        XCTAssertNotNil(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.tempListIdentifier)
        XCTAssertEqual(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.tempListIdentifier, mockExceptionsSource.tempListEtag)

        XCTAssertNotNil(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.allowListIdentifier)
        XCTAssertEqual(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.allowListIdentifier, mockExceptionsSource.allowListEtag)
        
        XCTAssertNotNil(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.unprotectedSitesIdentifier)
        XCTAssertEqual(cbrm.sourceManagers[mockRulesSource.rukeListName]?.brokenSources?.unprotectedSitesIdentifier, mockExceptionsSource.unprotectedSitesHash)

        XCTAssertEqual(cbrm.currentRules.first?.identifier,
                       ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                     tdsEtag: mockRulesSource.embeddedTrackerData.etag,
                                                     tempListEtag: nil,
                                                     allowListEtag: nil,
                                                     unprotectedSitesHash: nil))
    }
}

// swiftlint:enable type_body_length

class ContentBlockerRulesManagerUpdatingTests: ContentBlockerRulesManagerTests {

    private let rulesUpdateListener = RulesUpdateListener()
    
    func test_InvalidTDS_BeingFixed() {
        
        let mockRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: Self.makeDataSet(tds: Self.invalidRules, etag: Self.makeEtag()),
                                                                       embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        mockExceptionsSource.tempListEtag = Self.makeEtag()
        mockExceptionsSource.tempList = validTempSites
        
        XCTAssertNotEqual(mockRulesSource.trackerData?.etag, mockRulesSource.embeddedTrackerData.etag)
        
        let initialLoading = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            initialLoading.fulfill()
        }

        let cbrm = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                              exceptionsSource: mockExceptionsSource,
                                              updateListener: rulesUpdateListener,
                                              logger: .disabled)
        
        wait(for: [initialLoading], timeout: 15.0)

        XCTAssertEqual(cbrm.currentRules.first?.identifier,
                       ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                     tdsEtag: mockRulesSource.embeddedTrackerData.etag,
                                                     tempListEtag: mockExceptionsSource.tempListEtag,
                                                     allowListEtag: nil,
                                                     unprotectedSitesHash: nil))
        
        mockRulesSource.trackerData = Self.makeDataSet(tds: Self.validRules, etag: Self.makeEtag())
        
        let identifier = cbrm.currentRules.first?.identifier

        let updating = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            updating.fulfill()
        }

        cbrm.scheduleCompilation()
        
        wait(for: [updating], timeout: 15.0)

        XCTAssertEqual(cbrm.currentRules.first?.identifier.stringValue,
                       ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                     tdsEtag: mockRulesSource.trackerData?.etag ?? "\"\"",
                                                     tempListEtag: mockExceptionsSource.tempListEtag,
                                                     allowListEtag: nil,
                                                     unprotectedSitesHash: nil).stringValue)
        
        if let oldId = identifier, let newId = cbrm.currentRules.first?.identifier {
            let diff = oldId.compare(with: newId)
            
            XCTAssert(diff.contains(.tdsEtag))
            XCTAssertFalse(diff.contains(.tempListEtag))
            XCTAssertFalse(diff.contains(.unprotectedSites))
        } else {
            XCTFail("Missing identifiers")
        }
    }
    
    func test_InvalidTempList_BeingFixed() {
        
        let mockRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: Self.makeDataSet(tds: Self.validRules, etag: Self.makeEtag()),
                                                                       embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        mockExceptionsSource.tempListEtag = Self.makeEtag()
        mockExceptionsSource.tempList = invalidTempSites
        
        XCTAssertNotEqual(mockRulesSource.trackerData?.etag, mockRulesSource.embeddedTrackerData.etag)
        
        let initialLoading = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            initialLoading.fulfill()
        }

        let cbrm = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                              exceptionsSource: mockExceptionsSource,
                                              updateListener: rulesUpdateListener,
                                              logger: .disabled)
        
        wait(for: [initialLoading], timeout: 15.0)

        XCTAssertEqual(cbrm.currentRules.first?.identifier,
                       ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                     tdsEtag: mockRulesSource.embeddedTrackerData.etag,
                                                     tempListEtag: nil,
                                                     allowListEtag: nil,
                                                     unprotectedSitesHash: nil))
        
        mockExceptionsSource.tempListEtag = Self.makeEtag()
        mockExceptionsSource.tempList = validTempSites
        
        let identifier = cbrm.currentRules.first?.identifier

        let updating = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            updating.fulfill()
        }
        
        cbrm.scheduleCompilation()
        
        wait(for: [updating], timeout: 15.0)

        XCTAssertEqual(cbrm.currentRules.first?.identifier,
                       ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                     tdsEtag: mockRulesSource.trackerData?.etag ?? "\"\"",
                                                     tempListEtag: mockExceptionsSource.tempListEtag,
                                                     allowListEtag: nil,
                                                     unprotectedSitesHash: nil))
        
        if let oldId = identifier, let newId = cbrm.currentRules.first?.identifier {
            let diff = oldId.compare(with: newId)
            
            XCTAssert(diff.contains(.tdsEtag))
            XCTAssert(diff.contains(.tempListEtag))
            XCTAssertFalse(diff.contains(.unprotectedSites))
        } else {
            XCTFail("Missing identifiers")
        }
    }

    func test_InvalidAllowList_BeingFixed() {

        let mockRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: Self.makeDataSet(tds: Self.validRules, etag: Self.makeEtag()),
                                                                       embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        mockExceptionsSource.allowListEtag = Self.makeEtag()
        mockExceptionsSource.allowList = invalidAllowList

        XCTAssertNotEqual(mockRulesSource.trackerData?.etag, mockRulesSource.embeddedTrackerData.etag)

        let initialLoading = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            initialLoading.fulfill()
        }

        let cbrm = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                              exceptionsSource: mockExceptionsSource,
                                              updateListener: rulesUpdateListener,
                                              logger: .disabled)

        wait(for: [initialLoading], timeout: 15.0)

        XCTAssertEqual(cbrm.currentRules.first?.identifier,
                       ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                     tdsEtag: mockRulesSource.embeddedTrackerData.etag,
                                                     tempListEtag: nil,
                                                     allowListEtag: nil,
                                                     unprotectedSitesHash: nil))

        mockExceptionsSource.allowListEtag = Self.makeEtag()
        mockExceptionsSource.allowList = validAllowList

        let identifier = cbrm.currentRules.first?.identifier

        let updating = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            updating.fulfill()
        }

        cbrm.scheduleCompilation()

        wait(for: [updating], timeout: 15.0)

        XCTAssertEqual(cbrm.currentRules.first?.identifier,
                       ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                     tdsEtag: mockRulesSource.trackerData?.etag ?? "\"\"",
                                                     tempListEtag: nil,
                                                     allowListEtag: mockExceptionsSource.allowListEtag,
                                                     unprotectedSitesHash: nil))

        if let oldId = identifier, let newId = cbrm.currentRules.first?.identifier {
            let diff = oldId.compare(with: newId)

            XCTAssert(diff.contains(.tdsEtag))
            XCTAssert(diff.contains(.allowListEtag))
            XCTAssertFalse(diff.contains(.unprotectedSites))
        } else {
            XCTFail("Missing identifiers")
        }
    }
    
    func test_InvalidUnprotectedSites_BeingFixed() {

        let mockRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: Self.makeDataSet(tds: Self.validRules, etag: Self.makeEtag()),
                                                                       embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        mockExceptionsSource.tempListEtag = Self.makeEtag()
        mockExceptionsSource.tempList = validTempSites
        mockExceptionsSource.unprotectedSites = ["broken site Ltd. . 😉.com"]
        
        XCTAssertNotEqual(mockRulesSource.trackerData?.etag, mockRulesSource.embeddedTrackerData.etag)
        
        let initialLoading = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            initialLoading.fulfill()
        }

        let cbrm = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                              exceptionsSource: mockExceptionsSource,
                                              updateListener: rulesUpdateListener,
                                              logger: .disabled)
        
        wait(for: [initialLoading], timeout: 15.0)

        XCTAssertEqual(cbrm.currentRules.first?.identifier,
                       ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                     tdsEtag: mockRulesSource.embeddedTrackerData.etag,
                                                     tempListEtag: nil,
                                                     allowListEtag: nil,
                                                     unprotectedSitesHash: nil))
        
        mockExceptionsSource.unprotectedSites = ["example.com"]
        
        let identifier = cbrm.currentRules.first?.identifier

        let updating = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            updating.fulfill()
        }
        
        cbrm.scheduleCompilation()
        
        wait(for: [updating], timeout: 15.0)

        XCTAssertEqual(cbrm.currentRules.first?.identifier,
                       ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                     tdsEtag: mockRulesSource.trackerData?.etag ?? "\"\"",
                                                     tempListEtag: mockExceptionsSource.tempListEtag,
                                                     allowListEtag: nil,
                                                     unprotectedSitesHash: mockExceptionsSource.unprotectedSitesHash))
        
        if let oldId = identifier, let newId = cbrm.currentRules.first?.identifier {
            let diff = oldId.compare(with: newId)
            
            XCTAssert(diff.contains(.tdsEtag))
            XCTAssert(diff.contains(.tempListEtag))
            XCTAssert(diff.contains(.unprotectedSites))
        } else {
            XCTFail("Missing identifiers")
        }
    }

    func test_InvalidUnprotectedSites_StillBrokenAfterTempListUpdate() {

        let mockRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: Self.makeDataSet(tds: Self.validRules, etag: Self.makeEtag()),
                                                                       embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        mockExceptionsSource.tempListEtag = Self.makeEtag()
        mockExceptionsSource.tempList = validTempSites
        mockExceptionsSource.unprotectedSites = ["broken site Ltd. . 😉.com"]

        XCTAssertNotEqual(mockRulesSource.trackerData?.etag, mockRulesSource.embeddedTrackerData.etag)

        let initialLoading = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            initialLoading.fulfill()
        }

        let cbrm = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                              exceptionsSource: mockExceptionsSource,
                                              updateListener: rulesUpdateListener,
                                              logger: .disabled)

        wait(for: [initialLoading], timeout: 15.0)

        XCTAssertEqual(cbrm.currentRules.first?.identifier,
                       ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                     tdsEtag: mockRulesSource.embeddedTrackerData.etag,
                                                     tempListEtag: nil, allowListEtag: nil,
                                                     unprotectedSitesHash: nil))

        // New etag (testing update)
        mockExceptionsSource.tempListEtag = Self.makeEtag()

        let identifier = cbrm.currentRules.first?.identifier

        let updating = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            updating.fulfill()
        }

        cbrm.scheduleCompilation()

        wait(for: [updating], timeout: 15.0)

        XCTAssertEqual(cbrm.currentRules.first?.identifier,
                       ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                     tdsEtag: mockRulesSource.embeddedTrackerData.etag,
                                                     tempListEtag: nil,
                                                     allowListEtag: nil,
                                                     unprotectedSitesHash: nil))

        if let oldId = identifier, let newId = cbrm.currentRules.first?.identifier {
            XCTAssertEqual(oldId, newId)
        } else {
            XCTFail("Missing identifiers")
        }
    }
}

class MockSimpleContentBlockerRulesListsSource: ContentBlockerRulesListsSource {
    
    var trackerData: TrackerDataManager.DataSet? {
        didSet {
            contentBlockerRulesLists = [ContentBlockerRulesList(name: rukeListName,
                                                                trackerData: trackerData,
                                                                fallbackTrackerData: embeddedTrackerData)]
        }
    }
    var embeddedTrackerData: TrackerDataManager.DataSet {
        didSet {
            contentBlockerRulesLists = [ContentBlockerRulesList(name: rukeListName,
                                                                trackerData: trackerData,
                                                                fallbackTrackerData: embeddedTrackerData)]
        }
    }
    
    var contentBlockerRulesLists: [ContentBlockerRulesList]
    
    var rukeListName = DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName
    
    init(trackerData: TrackerDataManager.DataSet?, embeddedTrackerData: TrackerDataManager.DataSet) {
        self.trackerData = trackerData
        self.embeddedTrackerData = embeddedTrackerData
        
        contentBlockerRulesLists = [ContentBlockerRulesList(name: rukeListName,
                                                            trackerData: trackerData,
                                                            fallbackTrackerData: embeddedTrackerData)]
    }
    
}

class MockContentBlockerRulesExceptionsSource: ContentBlockerRulesExceptionsSource {

    var tempListEtag: String = ""
    var tempList: [String] = []
    var allowListEtag: String = ""
    var allowList: [TrackerException] = []
    var unprotectedSites: [String] = []
    
    var unprotectedSitesHash: String {
        return ContentBlockerRulesIdentifier.hash(domains: unprotectedSites)
    }
}
// swiftlint:enable file_length
