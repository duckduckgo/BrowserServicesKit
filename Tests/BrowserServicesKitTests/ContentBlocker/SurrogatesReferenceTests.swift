//
//  TrackerAllowlistReferenceTests.swift
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
@testable import TrackerRadarKit
import os.log
import WebKit
import BrowserServicesKit
import Common

final class SurrogatesReferenceTests: XCTestCase {
    let schemeHandler = TestSchemeHandler()
    var mockWebsite: MockWebsite!
    let userScriptDelegateMock = MockSurrogatesUserScriptDelegate()
    let navigationDelegateMock = MockNavigationDelegate()
    let tld = TLD()
    var redirectTests = [RefTests.Test]()

    var webView: WKWebView!

    private enum Resource {
        static let trackerRadar = "Resources/privacy-reference-tests/tracker-radar-tests/TR-domain-matching/tracker_radar_reference.json"
        static let tests = "Resources/privacy-reference-tests/tracker-radar-tests/TR-domain-matching/domain_matching_tests.json"
        static let surrogates = "Resources/privacy-reference-tests/tracker-radar-tests/TR-domain-matching/surrogates.txt"
    }
    
    func testSurrogates() throws {
        let data = JsonTestDataLoader()
        
        let trackerRadarJSONData = data.fromJsonFile(Resource.trackerRadar)
        let testsData = data.fromJsonFile(Resource.tests)
        let surrogatesData = data.fromJsonFile(Resource.surrogates)
        
        let refTests = try JSONDecoder().decode(RefTests.self, from: testsData)
        let surrogateTests = refTests.surrogateTests.tests
        
        let surrogateString = String(data: surrogatesData, encoding: .utf8)!
        
        let trackerData = try JSONDecoder().decode(TrackerData.self, from: trackerRadarJSONData)
        let encodedData = try? JSONEncoder().encode(trackerData)
        let encodedTrackerData = String(data: encodedData!, encoding: .utf8)!

        let rules = ContentBlockerRulesBuilder(trackerData: trackerData).buildRules(withExceptions: [],
                                                                                    andTemporaryUnprotectedDomains: [])
        
        let privacyConfig = WebKitTestHelper.preparePrivacyConfig(locallyUnprotected: [],
                                                                  tempUnprotected: [],
                                                                  trackerAllowlist: [:],
                                                                  contentBlockingEnabled: true,
                                                                  exceptions: [])

        let platformTests = surrogateTests.filter {
            let skip = $0.exceptPlatforms?.contains("ios-browser")
            return skip == false || skip == nil
        }
        
        redirectTests = platformTests.filter {
            $0.expectAction == "redirect"
        }
        
        let notRedirectTests = platformTests.filter {
            $0.expectAction != "redirect"
        }
        
        for test in notRedirectTests {
            os_log("TEST: %s", test.name)
            let requestURL = URL(string: test.requestURL)!
            let siteURL = URL(string: test.siteURL)!
            let requestType = ContentBlockerRulesBuilder.resourceMapping[test.requestType]
            let rule = rules.matchURL(url: requestURL, topLevel: siteURL, resourceType: requestType!)
            let result = rule?.action
            
            if test.expectAction == "block" {
                XCTAssertEqual(result, .block())
            } else if test.expectAction == "ignore" {
                XCTAssertTrue(result == nil || result == .ignorePreviousRules())
            }
        }
        
        let testsExecuted = expectation(description: "tests executed")
        testsExecuted.expectedFulfillmentCount = redirectTests.count

        createWebViewForUserScripTests(trackerData: trackerData,
                                       encodedTrackerData: encodedTrackerData,
                                       surrogates: surrogateString,
                                       privacyConfig: privacyConfig) { webview in
            
            self.webView = webview
            self.runTestForRedirect(onTestExecuted: testsExecuted)
        }
        
        waitForExpectations(timeout: 30, handler: nil)
    }
    
    private func runTestForRedirect(onTestExecuted: XCTestExpectation) {
        
        guard let test = redirectTests.popLast(),
              let expectedRedirect = test.expectRedirect else {
            return
        }
        
        
        let requestURL = URL(string: test.requestURL.testSchemeNormalized)!
        let siteURL = URL(string: test.siteURL.testSchemeNormalized)!
        
        let resource = MockWebsite.EmbeddedResource(type: .script,
                                                    url: requestURL)

        mockWebsite = MockWebsite(resources: [resource])
        print("---------")
        print("RequestURL: \(requestURL)\nSiteURL: \(siteURL)\nExpectedRedirect: \(expectedRedirect)")
        print("HTML REPRESENTATION [\(mockWebsite.htmlRepresentation)] -- ")

        schemeHandler.reset()
        schemeHandler.requestHandlers[siteURL] = { _ in
            return self.mockWebsite.htmlRepresentation.data(using: .utf8)!
        }

        //os_log("Loading %s ...", siteURL.absoluteString)
        let request = URLRequest(url: siteURL)

        WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeDiskCache,
                                                          WKWebsiteDataTypeMemoryCache,
                                                          WKWebsiteDataTypeOfflineWebApplicationCache],
                                                modifiedSince: Date(timeIntervalSince1970: 0),
                                                completionHandler: {
            self.webView.load(request)
        })
        
        /*
         surrogates.test/tracker application/javascript
         (() => {
             'use strict';
             var surrogatesScriptTest = function() {
                 function ping() {
                     return "success"
                 }
                 return {
                     ping: ping
                 }
             }()
             window.surrT = surrogatesScriptTest
         })();

         */

        navigationDelegateMock.onDidFinishNavigation = {

            XCTAssertEqual(self.userScriptDelegateMock.detectedSurrogates.count, 1)
            
            #warning("this works, which means it's being ran")
            if let request = self.userScriptDelegateMock.detectedSurrogates.first {
                print("REQUES \(request) ISBLOC \(request.isBlocked)")
            }
                    
            self.userScriptDelegateMock.reset()
            
            #warning("HTML never displays the (function() {var tracker=true})();")
            
            self.webView?.evaluateJavaScript("document.documentElement.outerHTML", completionHandler: { result, err in
                XCTAssertNil(err)
                
                if let result = result as? String {
                    print("HTML \(result)")
                    onTestExecuted.fulfill()
                    
                    DispatchQueue.main.async {
                        self.runTestForRedirect(onTestExecuted: onTestExecuted)
                    }
                }
            })
            
            //This Works
//            self.webView?.evaluateJavaScript("window.surrT.ping()", completionHandler: { result, err in
//                XCTAssertNil(err)
//
//                if let result = result as? String {
//                    XCTAssertEqual(result, "success")
//                    onTestExecuted.fulfill()
//
//                    DispatchQueue.main.async {
//                        self.runTestForRedirect(onTestExecuted: onTestExecuted)
//                    }
//                }
//            })
            
//            self.webView.evaluateJavaScript("tracker === true", completionHandler: { result, error in
//                if let datHtml = result as? String {
//                    print("MY HTML \(datHtml)")
//                    print("EXPECTED \(expectedRedirect)")
//                    onTestExecuted.fulfill()
//
//                    DispatchQueue.main.async {
//                        self.runTestForRedirect(onTestExecuted: onTestExecuted)
//                    }
//                }
//            })
        }
    }
    
    private func createWebViewForUserScripTests(trackerData: TrackerData,
                                                encodedTrackerData: String,
                                                surrogates: String,
                                                privacyConfig: PrivacyConfiguration,
                                                completion: @escaping (WKWebView) -> Void) {
        
        var tempUnprotected = privacyConfig.tempUnprotectedDomains.filter { !$0.trimmingWhitespace().isEmpty }
        tempUnprotected.append(contentsOf: privacyConfig.exceptionsList(forFeature: .contentBlocking))

        let exceptions = DefaultContentBlockerRulesExceptionsSource.transform(allowList: privacyConfig.trackerAllowlist)

        WebKitTestHelper.prepareContentBlockingRules(trackerData: trackerData,
                                                     exceptions: privacyConfig.userUnprotectedDomains,
                                                     tempUnprotected: tempUnprotected,
                                                     trackerExceptions: exceptions) { rules in
            guard let rules = rules else {
                XCTFail("Rules were not compiled properly")
                return
            }

            let configuration = WKWebViewConfiguration()
            configuration.setURLSchemeHandler(self.schemeHandler, forURLScheme: self.schemeHandler.scheme)

            let webView = WKWebView(frame: .init(origin: .zero, size: .init(width: 500, height: 1000)),
                                 configuration: configuration)
            webView.navigationDelegate = self.navigationDelegateMock

            let config = TestSchemeSurrogatesUserScriptConfig(privacyConfig: privacyConfig,
                                                              surrogates: surrogates,
                                                              trackerData: trackerData,
                                                              encodedSurrogateTrackerData: encodedTrackerData,
                                                              tld: self.tld,
                                                              isDebugBuild: true)

            let userScript = SurrogatesUserScript(configuration: config)
            userScript.delegate = self.userScriptDelegateMock

            for messageName in userScript.messageNames {
                configuration.userContentController.add(userScript, name: messageName)
            }

            configuration.userContentController.addUserScript(WKUserScript(source: userScript.source,
                                                                           injectionTime: .atDocumentStart,
                                                                           forMainFrameOnly: false))
            configuration.userContentController.add(rules)

            completion(webView)
        }
    }
}
