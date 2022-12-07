//
//  ExpireFirstPartyCookieReferenceTests.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
@testable import TrackerRadarKit
@testable import BrowserServicesKit
import WebKit
import Common
import os.log

final class ExpireFirstPartyCookieReferenceTests: XCTestCase {
    private var referenceTests = [Test]()
    private let schemeHandler = TestSchemeHandler()
    private let navigationDelegateMock = MockNavigationDelegate()
    private let tld = TLD()
    private let dataLoader = JsonTestDataLoader()
    private var webView: WKWebView!
    private var mockWebsite: MockWebsite!

    private enum Resource {
        static let config = "Resources/privacy-reference-tests/expire-first-party-js-cookies/config_reference.json"
        static let tests = "Resources/privacy-reference-tests/expire-first-party-js-cookies/tests.json"
        static let tracker = "Resources/privacy-reference-tests/expire-first-party-js-cookies/tracker_radar_reference.json"
    }
    
    private lazy var dateFormatter: DateFormatter =  {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return dateFormatter
    }()
    
    private lazy var privacyManager: PrivacyConfigurationManager = {
        let configJSONData = dataLoader.fromJsonFile(Resource.config)
        let embeddedDataProvider = MockEmbeddedDataProvider(data: configJSONData,
                                                            etag: "embedded")
        let localProtection = MockDomainsProtectionStore()
        localProtection.unprotectedDomains = []
        return PrivacyConfigurationManager(fetchedETag: nil,
                                           fetchedData: nil,
                                           embeddedDataProvider: embeddedDataProvider,
                                           localProtection: localProtection)
    }()
    
    private lazy var trackerData: TrackerData = {
        let trackerJSONData = dataLoader.fromJsonFile(Resource.tracker)
        return try! JSONDecoder().decode(TrackerData.self, from: trackerJSONData)
    }()

    func testFirstPartyCookies() throws {
        
//        let rules = ContentBlockerRulesBuilder(trackerData: trackerData).buildRules(withExceptions:[],andTemporaryUnprotectedDomains: [])
        
        let testData = dataLoader.fromJsonFile(Resource.tests)
        referenceTests =  try JSONDecoder().decode(TestData.self, from: testData).expireFirstPartyTrackingCookies.tests

        let testsExecuted = expectation(description: "tests executed")
        testsExecuted.expectedFulfillmentCount = referenceTests.count

        runTestForCookies(onTestExecuted: testsExecuted)
        waitForExpectations(timeout: 30, handler: nil)
    }

    private func runTestForCookies(onTestExecuted: XCTestExpectation) {
        guard let test = referenceTests.popLast() else {
            return
        }
        
        os_log("TEST: %s", test.name)
        
        let requestURL = URL(string: test.siteURL.testSchemeNormalized)!
        let scriptURL = URL(string: test.scriptURL.testSchemeNormalized)!
        
        let resource = MockWebsite.EmbeddedResource(type: .script,
                                                    url: scriptURL)
        
        mockWebsite = MockWebsite(resources: [resource])
        
        schemeHandler.reset()
        schemeHandler.requestHandlers[requestURL] = { _ in
            return self.mockWebsite.htmlRepresentation.data(using: .utf8)!
        }
        
        let request = URLRequest(url: requestURL)

        setupWebViewForUserScripTests(trackerData: trackerData,
                                      schemeHandler: schemeHandler,
                                      privacyConfig: privacyManager.privacyConfig) { webView in
            // Keep webview in memory till test finishes
            self.webView = webView
            
            WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeDiskCache,
                                                              WKWebsiteDataTypeMemoryCache,
                                                              WKWebsiteDataTypeOfflineWebApplicationCache],
                                                    modifiedSince: Date(timeIntervalSince1970: 0),
                                                    completionHandler: {
                
                if let cookie = self.cookieForTest(test) {
                    print("COOKIE CREATED \(cookie)")
                    self.webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
                }
                
                self.webView.load(request)
            })
            
        }
        
        navigationDelegateMock.onDidFinishNavigation = {
            
            self.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                print("COOKIE ON DID FINISH \(cookies)")
                if test.expectCookieSet {
                    XCTAssertTrue(cookies.count == 1, "Should have one cookie: \(test.name)")
                    if let cookie = cookies.first {
                        if test.expectExpiryToBe == -1 {
                            // expect(cookie.isSessionCookie()).toBe(true)
                            XCTAssertTrue(cookie.isSessionOnly, "Cookie should be session only \(test.name)")
                        } else {
                            XCTAssertFalse(cookie.isSessionOnly, "Cookie should not be session only \(test.name)")
                            
                            if let creationDateInterval = cookie.properties?[HTTPCookiePropertyKey("Created")] as? Int,
                               let cookieExpiresDate = cookie.expiresDate {
                                
                                
                                let creationDate = Date(timeIntervalSinceReferenceDate: TimeInterval(creationDateInterval))
                                let timeInterval = cookieExpiresDate.timeIntervalSince(creationDate)
                                print("NAME \(test.name) TIME INTERVAL \(timeInterval), CREATION \(creationDate) EXPIRY \(cookieExpiresDate)")
                                XCTAssertEqual(timeInterval, TimeInterval(test.expectExpiryToBe ?? 0), "Time interval should be the same \(test.name)")
                            } else {
                                XCTFail("Test \(test.name) should have valid expiration and creation dates")
                            }
                        }
                    }
                    
                } else {
                    XCTAssertTrue(cookies.count == 0, "Should have zero cookie: \(test.name)")
                }
                
                // Delete Cookies
                for cookie in cookies {
                    self.webView.configuration.websiteDataStore.httpCookieStore.delete(cookie)
                }
                
                DispatchQueue.main.async {
                    onTestExecuted.fulfill()
                    self.runTestForCookies(onTestExecuted: onTestExecuted)
                }
            }
        }
    }
    
    private func cookieForTest(_ test: Test) -> HTTPCookie? {
        let cookiePropertiesDictionary = test.setDocumentCookie
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .reduce(into: [String: String]()) { result, item in
                let keyValue = item.split(separator: "=")
                
                if let key = keyValue.first,
                   let value = keyValue.last  {
                    result[String(key.lowercased())] = String(value)
                }
            }
        
        var cookieProperties = [HTTPCookiePropertyKey: Any]()
        
        if let path = cookiePropertiesDictionary["path"] {
            cookieProperties[.path] = path
        }
        
        if let value = cookiePropertiesDictionary["foo"] {
            cookieProperties[.value] = value
        }
        
        if let maxAge = cookiePropertiesDictionary["max-age"] {
            cookieProperties[.maximumAge] = maxAge
        }
        
        if let expires = cookiePropertiesDictionary["expires"] {
            cookieProperties[.expires] = dateFormatter.date(from: expires)
        }
        
        if let domain = cookiePropertiesDictionary["domain"] {
            cookieProperties[.domain] = domain
        }
        
        if let _ = cookiePropertiesDictionary["secure"] {
            cookieProperties[.secure] = true
        }
        
        cookieProperties[.version] = "1"
        cookieProperties[.name] = test.name
        print("Creating cookie for test \(test.name)\nProperties \(cookieProperties)")
        return HTTPCookie(properties: cookieProperties)
    }
    
    private func setupWebViewForUserScripTests(trackerData: TrackerData,
                                               schemeHandler: TestSchemeHandler,
                                               privacyConfig: PrivacyConfiguration,
                                               completion: @escaping (WKWebView) -> Void) {

        WebKitTestHelper.prepareContentBlockingRules(trackerData: trackerData,
                                                     exceptions: [],
                                                     tempUnprotected: [],
                                                     trackerExceptions: []) { rules in
            guard let rules = rules else {
                XCTFail("Rules were not compiled properly")
                return
            }

            let configuration = WKWebViewConfiguration()
            configuration.setURLSchemeHandler(schemeHandler, forURLScheme: schemeHandler.scheme)

            let webView = WKWebView(frame: .init(origin: .zero, size: .init(width: 500, height: 1000)),
                                 configuration: configuration)
            webView.navigationDelegate = self.navigationDelegateMock


            let config = DefaultContentBlockerUserScriptConfig(privacyConfiguration: privacyConfig,
                                                               trackerData: trackerData,
                                                               ctlTrackerData: nil,
                                                               tld: self.tld)
            
            let contentScopeScript = ContentScopeUserScript(self.privacyManager,
                                                            properties: ContentScopeProperties(gpcEnabled: false,
                                                                                               sessionKey: UUID().uuidString,
                                                                                               featureToggles: ContentScopeFeatureToggles(emailProtection: false,
                                                                                                                                          credentialsAutofill: false,
                                                                                                                                          identitiesAutofill: false,
                                                                                                                                          creditCardsAutofill: false,
                                                                                                                                          credentialsSaving: false,
                                                                                                                                          passwordGeneration: false,
                                                                                                                                          inlineIconCredentials: false,
                                                                                                                                          thirdPartyCredentialsProvider: false)))
            //  let userScript = ContentBlockerRulesUserScript(configuration: config)
            
            for messageName in contentScopeScript.messageNames {
                configuration.userContentController.add(contentScopeScript, name: messageName)
            }

            configuration.userContentController.addUserScript(WKUserScript(source: contentScopeScript.source,
                                                                           injectionTime: .atDocumentStart,
                                                                           forMainFrameOnly: false))
            configuration.userContentController.add(rules)

            completion(webView)
        }
    }
}

// MARK: - TestData
private struct TestData: Codable {
    let expireFirstPartyTrackingCookies: ExpireFirstPartyTrackingCookies
}

// MARK: - ExpireFirstPartyTrackingCookies
private struct ExpireFirstPartyTrackingCookies: Codable {
    let name, desc: String
    let tests: [Test]
}

// MARK: - Test
private struct Test: Codable {
    let name: String
    let siteURL: String
    let scriptURL: String
    let setDocumentCookie: String
    let expectCookieSet: Bool
    let expectExpiryToBe: Int?
    let exceptPlatforms: [String]
}
