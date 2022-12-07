//
//  FingerprintingReferenceTests.swift
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

/*
 for $testSet in test.json
   loadReferenceConfig('config_reference.json')

     for $test in $testSet
         if $test.exceptPlatforms includes 'current-platform'
             skip

         $page = createPage(
             siteURL = $test.siteURL,
         )

         $page.load('init.js')

         $value = $page.eval($test.property)

         expect($value.toSting()).toBe($test.expectPropertyValue)
 */

final class FingerprintingReferenceTests: XCTestCase {
    private var referenceTests = [Test]()
    private let schemeHandler = TestSchemeHandler()
    private let navigationDelegateMock = MockNavigationDelegate()
    private let tld = TLD()
    private let dataLoader = JsonTestDataLoader()
    private var webView: WKWebView!
    private var mockWebsite: MockWebsite!

    private enum Resource {
        static let script = "Resources/privacy-reference-tests/fingerprinting-protections/init.js"
        static let config = "Resources/privacy-reference-tests/fingerprinting-protections/config_reference.json"
        static let tests = "Resources/privacy-reference-tests/fingerprinting-protections/tests.json"
    }
    
    private lazy var testData: TestData = {
        let testData = dataLoader.fromJsonFile(Resource.tests)
        return try! JSONDecoder().decode(TestData.self, from: testData)
    }()
    
    private lazy var scriptToInject: String = {
        let scriptData = dataLoader.fromJsonFile(Resource.script)
        return String(data: scriptData, encoding: .utf8)!
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

    override func tearDown() {
        super.tearDown()
        referenceTests.removeAll()
    }

    func testBatteryAPI() throws {
        referenceTests = testData.batteryAPI.tests
        os_log("TEST SECTION: %s", testData.batteryAPI.name)
        
        let testsExecuted = expectation(description: "tests executed")
        testsExecuted.expectedFulfillmentCount = referenceTests.count

        runTests(onTestExecuted: testsExecuted)
        waitForExpectations(timeout: 30, handler: nil)
    }
    
    func testHardwareAPI() throws {
        referenceTests =  testData.hardwareAPIs.tests
        os_log("TEST SECTION: %s", testData.hardwareAPIs.name)
        
        let testsExecuted = expectation(description: "tests executed")
        testsExecuted.expectedFulfillmentCount = referenceTests.count

        runTests(onTestExecuted: testsExecuted)
        waitForExpectations(timeout: 30, handler: nil)
    }
    
    func testScreenAPI() throws {
        referenceTests =  testData.screenAPI.tests
        os_log("TEST SECTION: %s", testData.screenAPI.name)

        let testsExecuted = expectation(description: "tests executed")
        testsExecuted.expectedFulfillmentCount = referenceTests.count

        runTests(onTestExecuted: testsExecuted)
        waitForExpectations(timeout: 30, handler: nil)
    }
    
    func testStorageAPI() throws {
        referenceTests = testData.temporaryStorageAPI.tests
        os_log("TEST SECTION: %s", testData.temporaryStorageAPI.name)
        
        let testsExecuted = expectation(description: "tests executed")
        testsExecuted.expectedFulfillmentCount = referenceTests.count

        runTests(onTestExecuted: testsExecuted)
        waitForExpectations(timeout: 30, handler: nil)
    }
    
    private func runTests(onTestExecuted: XCTestExpectation) {
        guard let test = referenceTests.popLast(),
              test.exceptPlatforms.contains("macos-browser") == false else {
            return
        }
        
        os_log("TEST: %s", test.name)
        
        let requestURL = URL(string: test.siteURL.testSchemeNormalized)!

        schemeHandler.reset()
        schemeHandler.requestHandlers[requestURL] = { _ in
            return "<html></html>".data(using: .utf8)!
        }
        
        let request = URLRequest(url: requestURL)

        setupWebViewForUserScripTests(schemeHandler: schemeHandler,
                                      privacyConfig: privacyManager.privacyConfig) { webView in
            // Keep webview in memory till test finishes
            self.webView = webView
            
            WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeDiskCache,
                                                              WKWebsiteDataTypeMemoryCache,
                                                              WKWebsiteDataTypeOfflineWebApplicationCache],
                                                    modifiedSince: Date(timeIntervalSince1970: 0),
                                                    completionHandler: {

                
                self.webView.load(request)
            })
            
        }
        
        navigationDelegateMock.onDidFinishNavigation = { [weak self] in
            
            self!.webView.evaluateJavaScript(self!.scriptToInject, completionHandler: { result, err in
                XCTAssertNil(err, "Script should not fail")
                
                self!.webView.evaluateJavaScript(test.property) { result, error in
                    if let result = result as? String {
                        print("AAA \(result)")
                        XCTAssertEqual(result, test.expectPropertyValue, "Values should be equal for test: \(test.name)")
                    } else if let result = result as? Bool {
                        let expectedBool = test.expectPropertyValue == "0" ? false : true
                        XCTAssertEqual(result, expectedBool, "Values should be equal for test: \(test.name)")
                    } else if let result = result as? Int {
                        XCTAssertEqual(result, Int(test.expectPropertyValue), "Values should be equal for test: \(test.name)")
                    }
                    
                    DispatchQueue.main.async {
                        onTestExecuted.fulfill()
                        self!.runTests(onTestExecuted: onTestExecuted)
                    }
                }
            })
        }
    }
    
    private func setupWebViewForUserScripTests(schemeHandler: TestSchemeHandler,
                                               privacyConfig: PrivacyConfiguration,
                                               completion: @escaping (WKWebView) -> Void) {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: schemeHandler.scheme)
        
        let webView = WKWebView(frame: .init(origin: .zero, size: .init(width: 500, height: 1000)),
                                configuration: configuration)
        webView.navigationDelegate = self.navigationDelegateMock
        
        let configFeatureToggle = ContentScopeFeatureToggles(emailProtection: false,
                                                             credentialsAutofill: false,
                                                             identitiesAutofill: false,
                                                             creditCardsAutofill: false,
                                                             credentialsSaving: false,
                                                             passwordGeneration: false,
                                                             inlineIconCredentials: false,
                                                             thirdPartyCredentialsProvider: false)
        
        let contentScopeProperties = ContentScopeProperties(gpcEnabled: false,
                                                            sessionKey: UUID().uuidString,
                                                            featureToggles: configFeatureToggle)
        
        let contentScopeScript = ContentScopeUserScript(self.privacyManager,
                                                        properties: contentScopeProperties)
        
        for messageName in contentScopeScript.messageNames {
            configuration.userContentController.add(contentScopeScript, name: messageName)
        }
        
        configuration.userContentController.addUserScript(WKUserScript(source: contentScopeScript.source,
                                                                       injectionTime: .atDocumentStart,
                                                                       forMainFrameOnly: false))
        completion(webView)
    }
}


// MARK: - TestData
private struct TestData: Codable {
    let batteryAPI, hardwareAPIs, screenAPI, temporaryStorageAPI: TestSection
}

// MARK: - BatteryAPI
private struct TestSection: Codable {
    let name, desc: String
    let tests: [Test]
}

// MARK: - Test
private struct Test: Codable {
    let name: String
    let siteURL: String
    let property, expectPropertyValue: String
    let exceptPlatforms: [String]
}
