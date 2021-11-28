//
//  TrackerDataManagerTests.swift
//  Core
//
//  Copyright © 2019 DuckDuckGo. All rights reserved.
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
import CommonCrypto
@testable import BrowserServicesKit

class TrackerDataManagerTests: XCTestCase {
    
    func testWhenReloadCalledInitiallyThenDataSetIsEmbedded() {

        XCTAssertEqual(TrackerDataManager(etag: nil, data: nil).reload(etag: nil, data: nil), TrackerDataManager.ReloadResult.embedded)
    }

    func testFindTrackerByUrl() {
        let trackerDataManager = TrackerDataManager(etag: nil, data: nil)
        let tracker = trackerDataManager.embeddedData.tds.findTracker(forUrl: "http://googletagmanager.com")
        XCTAssertNotNil(tracker)
        XCTAssertEqual("Google", tracker?.owner?.displayName)
    }
    
    func testFindEntityByName() {
        let trackerDataManager = TrackerDataManager(etag: nil, data: nil)
        let entity = trackerDataManager.embeddedData.tds.findEntity(byName: "Google LLC")
        XCTAssertNotNil(entity)
        XCTAssertEqual("Google", entity?.displayName)
    }
    
    func testFindEntityForHost() {
        let trackerDataManager = TrackerDataManager(etag: nil, data: nil)
        let entity = trackerDataManager.embeddedData.tds.findEntity(forHost: "www.google.com")
        XCTAssertNotNil(entity)
        XCTAssertEqual("Google", entity?.displayName)
    }
    
    // swiftlint:disable function_body_length
    func testWhenDownloadedDataAvailableThenReloadUsesIt() {

        let update = """
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


        let trackerDataManager = TrackerDataManager(etag: nil, data: nil)
        
        XCTAssertEqual(trackerDataManager.embeddedData.etag, TrackerDataManager.Constants.embeddedDataSetETag)
        XCTAssertEqual(trackerDataManager.reload(etag: "new etag", data: update.data(using: .utf8)), TrackerDataManager.ReloadResult.downloaded)
        XCTAssertEqual(trackerDataManager.fetchedData?.etag, "new etag")
        XCTAssertNil(trackerDataManager.fetchedData?.tds.findEntity(byName: "Google LLC"))
        XCTAssertNotNil(trackerDataManager.fetchedData?.tds.findEntity(byName: "Not Real"))

    }
    // swiftlint:enable function_body_length
        
    func testWhenEmbeddedDataIsUpdatedThenUpdateSHAAndEtag() throws {
        
        let hash = try Data(contentsOf: TrackerDataManager.embeddedUrl).sha256
    print(hash)
        XCTAssertEqual(hash, TrackerDataManager.Constants.embeddedDataSetSHA, "Error: please update SHA and ETag when changing embedded TDS")
    }
}
