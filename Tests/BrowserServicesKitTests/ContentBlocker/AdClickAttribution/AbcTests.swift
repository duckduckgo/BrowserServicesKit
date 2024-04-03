//
//  AbcTests.swift
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
import WebKit
import BrowserServicesKit
import TrackerRadarKit
import Common

class AbcTests: XCTestCase {

    let exampleTDS = """
{
    "trackers": {
        "example.com": {
            "domain": "example.com",
            "owner": {
                "name": "Example Limited",
                "displayName": "Example Ltd"
            },
            "prevalence": 0.0001,
            "fingerprinting": 1,
            "cookies": 0,
            "categories": [],
            "default": "block"
        }
    },
    "entities": {
        "Example Limited": {
            "domains": [
                "example.com"
            ],
            "prevalence": 1,
            "displayName": "Example Ltd"
        }
    },
    "domains": {
        "example.com": "Example Limited"
    },
    "cnames": {}
}
""".data(using: .utf8)!

    let schemeHandler = TestSchemeHandler()
    let userScriptDelegateMock = MockRulesUserScriptDelegate()
    let navigationDelegateMock = MockNavigationDelegate()
    let tld = TLD()

    var webView: WKWebView!
    var tds: TrackerData!

    func setupWebViewForUserScripTests(trackerData: TrackerData,
                                       userScriptDelegate: ContentBlockerRulesUserScriptDelegate,
                                       schemeHandler: TestSchemeHandler,
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

            let privacyConfig = WebKitTestHelper.preparePrivacyConfig(locallyUnprotected: [],
                                                                      tempUnprotected: [],
                                                                      trackerAllowlist: [:],
                                                                      contentBlockingEnabled: true,
                                                                      exceptions: [])

            let config = DefaultContentBlockerUserScriptConfig(privacyConfiguration: privacyConfig,
                                                               trackerData: trackerData,
                                                               ctlTrackerData: nil,
                                                               tld: self.tld)

            let userScript = ContentBlockerRulesUserScript(configuration: config)
            userScript.delegate = userScriptDelegate

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

    func testDomainMatching() throws {
        tds = try JSONDecoder().decode(TrackerData.self, from: exampleTDS)
        let testExecuted = expectation(description: "test executed")

        setupWebViewForUserScripTests(trackerData: tds,
                                      userScriptDelegate: userScriptDelegateMock,
                                      schemeHandler: schemeHandler) { [self] webView in
            self.webView = webView

            let siteURL = URL(string: "test://www.site.com/index.html")!
            let requestURL = URL(string: "test://www.example.com/convert.js")!

            let resource = MockWebsite.EmbeddedResource(type: .script, url: requestURL)
            let mockWebsite = MockWebsite(resources: [resource])

            schemeHandler.reset()
            schemeHandler.requestHandlers[siteURL] = { _ in
                return mockWebsite.htmlRepresentation.data(using: .utf8)!
            }

            userScriptDelegateMock.reset()

            os_log("Loading %s ...", siteURL.absoluteString)
            let request = URLRequest(url: siteURL)
            WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeDiskCache,
                                                              WKWebsiteDataTypeMemoryCache],
                                                    modifiedSince: Date(timeIntervalSince1970: 0),
                                                    completionHandler: {
                webView.load(request)
            })

            navigationDelegateMock.onDidFinishNavigation = {
                os_log("Website loaded")
                XCTAssertEqual(self.schemeHandler.handledRequests.count, 1)
                testExecuted.fulfill()
            }

        }

        waitForExpectations(timeout: 30, handler: nil)
    }

}
