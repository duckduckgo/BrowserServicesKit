//
//  AppPrivacyConfigurationTests.swift
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
import BrowserServicesKit

class MockPrivacyConfigurationDataProvider: PrivacyConfigurationEmbeddedDataProvider {
    var embeddedPrivacyConfigEtag: String

    var embeddedPrivacyConfig: Data

    init(data: Data, etag: String) {
        embeddedPrivacyConfig = data
        embeddedPrivacyConfigEtag = etag
    }
}

class AppPrivacyConfigurationTests: XCTestCase {

    let embeddedConfig =
    """
    {
        "features": {},
        "unprotectedTemporary": [
                { "domain": "domain1.com" },
                { "domain": "domain2.com" },
                { "domain": "domain3.com" },
        ]
    }
    """.data(using: .utf8)!
    let embeddedConfigETag = "embedded"

    let downloadedConfig =
    """
    {
        "features": {},
        "unprotectedTemporary": [
                { "domain": "domain1.com" },
                { "domain": "domain5.com" },
                { "domain": "domain6.com" },
        ]
    }
    """.data(using: .utf8)!
    let downloadedConfigETag = "downloaded"

    let corruptedConfig =
    """
    {
        "features": {},
        "unprotectedTemporary": [
    }
    """.data(using: .utf8)!
    let corruptedConfigETag = "corrupted"

    func testWhenDownloadedDataIsMissing_ThenEmbeddedIsUsed() {

        let mockEmbeddedData = MockPrivacyConfigurationDataProvider(data: embeddedConfig, etag: embeddedConfigETag)

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore())

        XCTAssertEqual(manager.embeddedConfigData.etag, mockEmbeddedData.embeddedPrivacyConfigEtag)
        XCTAssertEqual(manager.reload(etag: nil, data: nil), PrivacyConfigurationManager.ReloadResult.embedded)

        XCTAssertNil(manager.fetchedConfigData)

        let config = manager.privacyConfig
        XCTAssertFalse(config.isTempUnprotected(domain: "main1.com"))
        XCTAssertFalse(config.isTempUnprotected(domain: "notdomain1.com"))
        XCTAssertTrue(config.isTempUnprotected(domain: "domain1.com"))
        XCTAssertTrue(config.isTempUnprotected(domain: "domain2.com"))
        XCTAssertFalse(config.isTempUnprotected(domain: "domain5.com"))

        XCTAssertTrue(config.isTempUnprotected(domain: "www.domain1.com"))
    }


    func testWhenDataIsPresent_ThenItIsUsed() {

        let mockEmbeddedData = MockPrivacyConfigurationDataProvider(data: embeddedConfig, etag: embeddedConfigETag)

        let manager = PrivacyConfigurationManager(fetchedETag: downloadedConfigETag,
                                                  fetchedData: downloadedConfig,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore())

        XCTAssertEqual(manager.embeddedConfigData.etag, mockEmbeddedData.embeddedPrivacyConfigEtag)
        XCTAssertEqual(manager.fetchedConfigData?.etag, downloadedConfigETag)

        let config = manager.privacyConfig
        XCTAssertFalse(config.isTempUnprotected(domain: "main1.com"))
        XCTAssertFalse(config.isTempUnprotected(domain: "notdomain1.com"))
        XCTAssertTrue(config.isTempUnprotected(domain: "domain1.com"))
        XCTAssertFalse(config.isTempUnprotected(domain: "domain2.com"))
        XCTAssertTrue(config.isTempUnprotected(domain: "domain5.com"))

        XCTAssertTrue(config.isTempUnprotected(domain: "www.domain1.com"))
    }

    func testWhenDownloadedDataIsReloaded_ThenItIsUsed() {

        let mockEmbeddedData = MockPrivacyConfigurationDataProvider(data: embeddedConfig, etag: embeddedConfigETag)

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore())

        XCTAssertEqual(manager.embeddedConfigData.etag, mockEmbeddedData.embeddedPrivacyConfigEtag)
        XCTAssertNil(manager.fetchedConfigData)

        XCTAssertEqual(manager.reload(etag: downloadedConfigETag, data: downloadedConfig), .downloaded)

        let config = manager.privacyConfig
        XCTAssertFalse(config.isTempUnprotected(domain: "main1.com"))
        XCTAssertFalse(config.isTempUnprotected(domain: "notdomain1.com"))
        XCTAssertTrue(config.isTempUnprotected(domain: "domain1.com"))
        XCTAssertFalse(config.isTempUnprotected(domain: "domain2.com"))
        XCTAssertTrue(config.isTempUnprotected(domain: "domain5.com"))

        XCTAssertTrue(config.isTempUnprotected(domain: "www.domain1.com"))
    }

    func testWhenPresentDataIsCorrupted_ThenEmbeddedIsUsed() {

        let mockEmbeddedData = MockPrivacyConfigurationDataProvider(data: embeddedConfig, etag: embeddedConfigETag)

        let manager = PrivacyConfigurationManager(fetchedETag: corruptedConfigETag,
                                                  fetchedData: corruptedConfig,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore())

        XCTAssertEqual(manager.embeddedConfigData.etag, mockEmbeddedData.embeddedPrivacyConfigEtag)
        XCTAssertNil(manager.fetchedConfigData)

        // Should use embedded
        var config = manager.privacyConfig
        XCTAssertTrue(config.isTempUnprotected(domain: "domain1.com"))
        XCTAssertTrue(config.isTempUnprotected(domain: "domain2.com"))
        XCTAssertFalse(config.isTempUnprotected(domain: "domain5.com"))

        // Attempt fix
        XCTAssertEqual(manager.reload(etag: downloadedConfigETag, data: downloadedConfig), .downloaded)

        config = manager.privacyConfig
        XCTAssertTrue(config.isTempUnprotected(domain: "domain1.com"))
        XCTAssertFalse(config.isTempUnprotected(domain: "domain2.com"))
        XCTAssertTrue(config.isTempUnprotected(domain: "domain5.com"))
    }

    func testWhenReloadedDataIsCorrupted_ThenEmbeddedIsUsed() {

        let mockEmbeddedData = MockPrivacyConfigurationDataProvider(data: embeddedConfig, etag: embeddedConfigETag)

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore())

        XCTAssertEqual(manager.embeddedConfigData.etag, mockEmbeddedData.embeddedPrivacyConfigEtag)
        XCTAssertNil(manager.fetchedConfigData)

        // Should use embedded
        var config = manager.privacyConfig
        XCTAssertTrue(config.isTempUnprotected(domain: "domain1.com"))
        XCTAssertTrue(config.isTempUnprotected(domain: "domain2.com"))
        XCTAssertFalse(config.isTempUnprotected(domain: "domain5.com"))

        // Attempt fix
        XCTAssertEqual(manager.reload(etag: corruptedConfigETag, data: corruptedConfig), .embeddedFallback)

        config = manager.privacyConfig
        XCTAssertTrue(config.isTempUnprotected(domain: "domain1.com"))
        XCTAssertTrue(config.isTempUnprotected(domain: "domain2.com"))
        XCTAssertFalse(config.isTempUnprotected(domain: "domain5.com"))
    }

    func testWhenCheckingUnprotectedSites_ThenProtectionStoreIsUsed() {

        let mockEmbeddedData = MockPrivacyConfigurationDataProvider(data: embeddedConfig, etag: embeddedConfigETag)

        let mockProtectionStore = MockDomainsProtectionStore()
        mockProtectionStore.enableProtection(forDomain: "enabled.com")

        let manager = PrivacyConfigurationManager(fetchedETag: corruptedConfigETag,
                                                  fetchedData: corruptedConfig,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: mockProtectionStore)

        XCTAssertEqual(manager.embeddedConfigData.etag, mockEmbeddedData.embeddedPrivacyConfigEtag)
        XCTAssertNil(manager.fetchedConfigData)

        let config = manager.privacyConfig

        XCTAssertTrue(config.isUserUnprotected(domain: "enabled.com"))

        mockProtectionStore.enableProtection(forDomain: "enabled2.com")
        XCTAssertTrue(config.isUserUnprotected(domain: "enabled2.com"))
    }

}
