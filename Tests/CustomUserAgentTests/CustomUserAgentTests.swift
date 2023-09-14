//
//  CustomUserAgentTests.swift
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

import WebKit
import XCTest
import BrowserServicesKit
@testable import CustomUserAgent

final class CustomUserAgentTests: XCTestCase {

    private enum Constant {

        enum TestURL {

            static let example = URL(string: "http://example.com/index.html")!
            static let noAppURL = URL(string: "http://oas.com/index.html")!
            static let noAppSubdomainUrl = URL(string: "http://subdomain.oas.com/index.html")!
            static let noVersionURL = URL(string: "http://ovs.com/index.html")!
            static let noAppAndVersionURL = URL(string: "http://oavs.com/index.html")!
            static let noSafariURL = URL(string: "http://wvd.com/index.html")!
            static let exceptionURL = URL(string: "http://e.com/index.html")!
            static let unprotectedTemporaryURL = URL(string: "http://ut.com/index.html")!

        }

        enum DefaultAgent {

            static let phone = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
            static let desktop = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) AppleWebKit/605.1.15 (KHTML, like Gecko)"

        }

        enum ExpectedAgent {

            // swiftlint:disable line_length

            static let phone = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.4 Mobile/15E148 DuckDuckGo/7 Safari/605.1.15"
            static let desktop = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.4 DuckDuckGo/7 Safari/605.1.15"

            static let noApplication = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.4 Mobile/15E148 Safari/605.1.15"
            static let noVersion = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 DuckDuckGo/7 Safari/605.1.15"
            static let noApplicationAndVersion = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Safari/605.1.15"
            static let safari = noApplication
            static let webView = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
            static let webViewDesktop = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)"

            // Based on fallback constants in UserAgent
            static let mobileFallback = "Mozilla/5.0 (iPhone; CPU iPhone OS 13_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.5 Mobile/15E148 DuckDuckGo/7 Safari/605.1.15"
            static let desktopFallback = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.5 DuckDuckGo/7 Safari/605.1.15"

            // swiftlint:enable line_length

        }

        static let testConfig = """
        {
            "features": {
                "customUserAgent": {
                    "state": "enabled",
                    "settings": {
                        "omitApplicationSites": [
                            {
                                "domain": "oas.com",
                                "reason": "Site reports browser not supported"
                            },
                            {
                                "domain": "oavs.com",
                                "reason": "Site reports browser not supported"
                            }
                        ],
                        "omitVersionSites": [
                            {
                                "domain": "ovs.com",
                                "reason": "Site reports browser not supported"
                            },
                            {
                                "domain": "oavs.com",
                                "reason": "Site reports browser not supported"
                            }
                        ],
                        "webViewDefault": [
                            {
                                "domain": "wvd.com",
                                "reason": "Site reports browser not supported"
                            }
                        ]
                    },
                    "exceptions": [
                        {
                            "domain": "e.com",
                            "reason": "site breakage"
                        }
                    ]
                }
            },
            "unprotectedTemporary": [
                {
                    "domain": "ut.com",
                    "reason": "site breakage"
                }
            ]
        }
        """.data(using: .utf8)!

    }

    private var privacyConfig: PrivacyConfiguration!
    private let customUserAgent: CustomUserAgent.Type = {
        let customUserAgent = CustomUserAgent.self
        customUserAgent.configure(withAppMajorVersion: "7")
        customUserAgent.webView = Constant.DefaultAgent.phone
        customUserAgent.currentEnvironment = .iOS
        return customUserAgent
    }()

    override func setUp() {
        super.setUp()

        let mockEmbeddedData = MockEmbeddedDataProvider(data: Constant.testConfig, etag: "test")
        let mockProtectionStore = MockDomainsProtectionStore() // test it too

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: mockProtectionStore,
                                                  internalUserDecider: DefaultInternalUserDecider())

        privacyConfig = manager.privacyConfig

    }

    func testWhenPhoneUserAgentAndDesktopFalseThenPhoneAgentCreatedWithApplicationAndSafariSuffix() {
        XCTAssertEqual(Constant.ExpectedAgent.phone,
                       customUserAgent.for(Constant.TestURL.example, isFakingDesktop: false, privacyConfig: privacyConfig))
    }

    func testWhenPhoneUserAgentAndDesktopTrueThenDesktopAgentCreatedWithApplicationAndSafariSuffix() {
        XCTAssertEqual(Constant.ExpectedAgent.desktop,
                       customUserAgent.for(Constant.TestURL.example, isFakingDesktop: true, privacyConfig: privacyConfig))
    }

//    func testWhenNoUAAndDesktopFalseThenFallbackMobileAgentIsUsed() {
//        let testee = CustomUserAgent()
//        XCTAssertEqual(Constant.ExpectedAgent.mobileFallback, testee.calculate(for: Constant.TestURL.example, isDesktop: false, privacyConfig: privacyConfig))
//    }
//
//    func testWhenNoUaAndDesktopTrueThenFallbackDesktopAgentIsUsed() {
//        let testee = CustomUserAgent()
//        XCTAssertEqual(Constant.ExpectedAgent.desktopFallback, testee.calculate(for: Constant.TestURL.example, isDesktop: true, privacyConfig: privacyConfig))
//    }

    func testWhenPhoneUserAgentAndDesktopFalseAndDomainDoesNotSupportSafariUserAgentThenItDefaultsToWebViewUserAgent() {
        XCTAssertEqual(Constant.ExpectedAgent.webView,
                       customUserAgent.for(Constant.TestURL.noSafariURL, isFakingDesktop: false, privacyConfig: privacyConfig))
    }

    func testWhenPhoneUserAgentAndDesktopTrueAndDomainDoesNotSupportSafariUserAgentThenItDefaultsToDesktopWebViewUserAgent() {
        XCTAssertEqual(Constant.ExpectedAgent.webViewDesktop,
                       customUserAgent.for(Constant.TestURL.noSafariURL, isFakingDesktop: true, privacyConfig: privacyConfig))
    }

    func testWhenDomainDoesNotSupportApplicationComponentThenApplicationIsOmittedFromUA() {
        XCTAssertEqual(Constant.ExpectedAgent.noApplication,
                       customUserAgent.for(Constant.TestURL.noAppURL, isFakingDesktop: false, privacyConfig: privacyConfig))
    }

    func testWhenDomainDoesNotSupportVersionComponentThenVersionIsOmittedFromUA() {
        XCTAssertEqual(Constant.ExpectedAgent.noVersion,
                       customUserAgent.for(Constant.TestURL.noVersionURL, isFakingDesktop: false, privacyConfig: privacyConfig))
    }

    func testWhenDomainDoesNotSupportVersionAndApplicationComponentsThenVersionAndApplicationAreOmittedFromUA() {
        XCTAssertEqual(Constant.ExpectedAgent.noApplicationAndVersion,
                       customUserAgent.for(Constant.TestURL.noAppAndVersionURL, isFakingDesktop: false, privacyConfig: privacyConfig))
    }

    func testWhenDomainIsOnExceptionsListThenItDefaultsToSafariUA() {
        XCTAssertEqual(Constant.ExpectedAgent.safari,
                       customUserAgent.for(Constant.TestURL.exceptionURL, isFakingDesktop: false, privacyConfig: privacyConfig))
    }

    func testWhenDomainIsOnUnprotectedTemporaryListThenItDefaultsToSafariUA() {
        XCTAssertEqual(Constant.ExpectedAgent.safari,
                       customUserAgent.for(Constant.TestURL.unprotectedTemporaryURL, isFakingDesktop: false, privacyConfig: privacyConfig))
    }

//    func testWhenDomainIsOnUnprotectedTemporaryListThenItDefaultsToSafariUA() {
//        XCTAssertEqual(Constant.ExpectedAgent.noApplicationAndVersion,
//                       customUserAgent.for(Constant.TestURL.safari, isDesktop: false, privacyConfig: privacyConfig))
//    }

    func testWhenCustomUserAgentIsDisabledThenSafariUAIsUsedAsDefault() {
        let disabledConfig = """
        {
            "features": {
                "customUserAgent": {
                    "state": "disabled",
                    "settings": {
                        "omitApplicationSites": [
                            {
                                "domain": "cvs.com",
                                "reason": "Site breakage"
                            }
                        ]
                    },
                    "exceptions": []
                }
            },
            "unprotectedTemporary": []
        }
        """.data(using: .utf8)!

        let mockEmbeddedData = MockEmbeddedDataProvider(data: disabledConfig, etag: "test")
        let mockProtectionStore = MockDomainsProtectionStore()

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: mockProtectionStore,
                                                  internalUserDecider: DefaultInternalUserDecider())

        XCTAssertEqual(Constant.ExpectedAgent.safari, customUserAgent.for(Constant.TestURL.example,
                                                                          isFakingDesktop: false,
                                                                          privacyConfig: manager.privacyConfig))
    }
}

fileprivate final class MockInternalUserStoring: InternalUserStoring {
    var isInternalUser: Bool = false
}

fileprivate extension DefaultInternalUserDecider {
    convenience init(mockedStore: MockInternalUserStoring = MockInternalUserStoring()) {
        self.init(store: mockedStore)
    }
}

//todo: move to utils
fileprivate class MockEmbeddedDataProvider: EmbeddedDataProvider {
    var embeddedDataEtag: String

    var embeddedData: Data

    init(data: Data, etag: String) {
        embeddedData = data
        embeddedDataEtag = etag
    }
}

final class MockDomainsProtectionStore: DomainsProtectionStore {
    var unprotectedDomains = Set<String>()

    func disableProtection(forDomain domain: String) {
        unprotectedDomains.insert(domain)
    }

    func enableProtection(forDomain domain: String) {
        unprotectedDomains.remove(domain)
    }
}
