//
//  PrivacyConfigurationReferenceTests.swift
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
import os.log
import BrowserServicesKit

final class PrivacyConfigurationReferenceTests: XCTestCase {

    private enum Resource {
        static let configRootPath = "Resources/privacy-reference-tests/privacy-configuration"
        static let tests = "Resources/privacy-reference-tests/privacy-configuration/tests.json"
    }

    func testPrivacyConfiguration() throws {
        let dataLoader = JsonTestDataLoader()
        let testsData = dataLoader.fromJsonFile(Resource.tests)

        let referenceTests = try JSONDecoder().decode(TestData.self, from: testsData)

        for testConfig in referenceTests.testConfigs {
            let path = "\(Resource.configRootPath)/\(testConfig.referenceConfig)"

            let configData = dataLoader.fromJsonFile(path)
            let privacyConfigurationData = try PrivacyConfigurationData(data: configData)

            let privacyConfiguration = AppPrivacyConfiguration(data: privacyConfigurationData,
                                                               identifier: UUID().uuidString,
                                                               localProtection: MockDomainsProtectionStore(),
                                                               internalUserDecider: DefaultInternalUserDecider())
            for test in testConfig.tests {
                if test.exceptPlatforms.contains(.macosBrowser) || test.exceptPlatforms.contains(.iosBrowser) {
                    os_log("Skipping test %@", test.name)
                    continue
                }

                let testInfo = "\nName: \(test.name)\nFeature: \(test.featureName)\nsiteURL: \(test.siteURL)\nConfig: \(testConfig.referenceConfig)"

                guard let url = URL(string: test.siteURL),
                      let siteDomain = url.host else {
                    XCTFail("Can't get domain \(testInfo)")
                    continue
                }

                if let feature = PrivacyFeature(rawValue: test.featureName) {
                    let isEnabled = privacyConfiguration.isFeature(feature, enabledForDomain: siteDomain)
                    XCTAssertEqual(isEnabled, test.expectFeatureEnabled, testInfo)

                } else if test.featureName == "trackerAllowlist" {
                    let isEnabled = privacyConfigurationData.trackerAllowlist.state == "enabled"
                    XCTAssertEqual(isEnabled, test.expectFeatureEnabled, testInfo)

                } else {
                    XCTFail("Can't create feature \(testInfo)")
                    continue
                }
            }
        }
    }
}

// MARK: - TestData
private struct TestData: Codable {
    let testConfigs: [TestConfig]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let dict = try container.decode([String: TestConfig].self)
        testConfigs = dict.compactMap { _, values in values }
    }
}

// MARK: - TestConfig
private struct TestConfig: Codable {
    let name, desc, referenceConfig: String
    let tests: [Test]

}

// MARK: - Test
private struct Test: Codable {
    let name, featureName: String
    let siteURL: String
    let frameURL: String?
    let expectFeatureEnabled: Bool
    let exceptPlatforms: [ExceptPlatform]
    let scriptURL: String?
}

// MARK: - ExceptPlatform
private enum ExceptPlatform: String, Codable {
    case androidBrowser = "android-browser"
    case iosBrowser = "ios-browser"
    case macosBrowser = "macos-browser"
    case safariExtension = "safari-extension"
    case webExtension = "web-extension"
    case windowsBrowser = "windows-browser"
}
