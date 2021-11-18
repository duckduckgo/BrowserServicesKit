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
@testable import Core
@testable import DuckDuckGo
import BrowserServicesKit

class MockPrivacyConfigurationDataProvider: PrivacyConfigurationDataProvider {
    var embeddedPrivacyConfigEtag: String

    var embeddedPrivacyConfig: Data

    init(data: Data, etag: String) {
        embeddedPrivacyConfig = data
        embeddedPrivacyConfigEtag = etag
    }
}

private class MockDomainsProtectionStore: DomainsProtectionStore {
    var unprotectedDomains = Set<String>()

    func disableProtection(forDomain domain: String) {
        unprotectedDomains.remove(domain)
    }

    func enableProtection(forDomain domain: String) {
        unprotectedDomains.insert(domain)
    }

}

class AppPrivacyConfigurationTests: XCTestCase {

    func testWhenCheckingDomainsAreProtected_ThenUsesPersistedUnprotectedDomainList() {
        let configFile =
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
        _ = FileStore().persist(configFile, forConfiguration: .privacyConfiguration)
        XCTAssertEqual(AppContentBlocking.privacyConfigurationManager.embeddedConfigData.etag, AppPrivacyConfigurationDataProvider.Constants.embeddedConfigETag)
        XCTAssertEqual(AppContentBlocking.privacyConfigurationManager.reload(etag: nil, data: nil), .downloaded)

        let newConfig = AppContentBlocking.privacyConfigurationManager.fetchedConfigData
        XCTAssertNotNil(newConfig)

        if let newConfig = newConfig {
            XCTAssertEqual(newConfig.etag, "new etag")

            let config = AppPrivacyConfiguration(data: newConfig.data,
                                                 identifier: "",
                                                 localProtection: MockDomainsProtectionStore())

            XCTAssertFalse(config.isTempUnprotected(domain: "main1.com"))
            XCTAssertFalse(config.isTempUnprotected(domain: "notdomain1.com"))
            XCTAssertTrue(config.isTempUnprotected(domain: "domain1.com"))

            XCTAssertTrue(config.isTempUnprotected(domain: "www.domain1.com"))
        }
    }

}
