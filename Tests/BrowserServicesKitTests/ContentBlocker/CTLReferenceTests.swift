//
//  CTLReferenceTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

struct LocalClickToLoadRulesSplitter {

    public enum Constants {

        public static let clickToLoadRuleListPrefix = "CTL_"
        public static let tdsRuleListPrefix = "TDS_"

    }

    private let rulesList: ContentBlockerRulesList

    init(rulesList: ContentBlockerRulesList) {
        self.rulesList = rulesList
    }

    func split() -> (withoutBlockCTL: ContentBlockerRulesList, withBlockCTL: ContentBlockerRulesList)? {
        // This needs to be able to process cases when only fallback data is available.
        // Also needs to be cleaned up to avoid code duplication around return.

        if let trackerData = rulesList.trackerData {
            let splitTDS = split(trackerData: trackerData)
            return (
                ContentBlockerRulesList(name: rulesList.name,
                                        trackerData: splitTDS?.withoutBlockCTL,
                                        fallbackTrackerData: split(trackerData: rulesList.fallbackTrackerData)!.withoutBlockCTL),
                ContentBlockerRulesList(name: "CTL List name", // fixme
                                        trackerData: splitTDS?.withBlockCTL,
                                        fallbackTrackerData: split(trackerData: rulesList.fallbackTrackerData)!.withBlockCTL)
            )
        } else {
            return (
                ContentBlockerRulesList(name: rulesList.name,
                                        trackerData: nil,
                                        fallbackTrackerData: split(trackerData: rulesList.fallbackTrackerData)!.withoutBlockCTL),
                ContentBlockerRulesList(name: "CTL List name", // fixme
                                        trackerData: nil,
                                        fallbackTrackerData: split(trackerData: rulesList.fallbackTrackerData)!.withBlockCTL)
            )
        }


    }

    private func split(trackerData: TrackerDataManager.DataSet) -> (withoutBlockCTL: TrackerDataManager.DataSet, withBlockCTL: TrackerDataManager.DataSet)? {
        let (mainTrackers, ctlTrackers) = processCTLActions(trackerData.tds.trackers)
        guard !ctlTrackers.isEmpty else { return nil }

        let trackerDataWithoutBlockCTL = makeTrackerData(using: mainTrackers, originalTDS: trackerData.tds)
        let trackerDataWithBlockCTL = makeTrackerData(using: ctlTrackers, originalTDS: trackerData.tds)

        return (
           (tds: trackerDataWithoutBlockCTL, etag: Constants.tdsRuleListPrefix + trackerData.etag),
           (tds: trackerDataWithBlockCTL, etag: Constants.clickToLoadRuleListPrefix + trackerData.etag)
        )
    }

    private func makeTrackerData(using trackers: [String: KnownTracker], originalTDS: TrackerData) -> TrackerData {
        let entities = originalTDS.extractEntities(for: trackers)
        let domains = extractDomains(from: entities)
        return TrackerData(trackers: trackers,
                           entities: entities,
                           domains: domains,
                           cnames: originalTDS.cnames)
    }

    private func processCTLActions(_ trackers: [String: KnownTracker]) -> (mainTrackers: [String: KnownTracker], ctlTrackers: [String: KnownTracker]) {
        var mainTDSTrackers: [String: KnownTracker] = [:]
        var ctlTrackers: [String: KnownTracker] = [:]

        for (key, tracker) in trackers {
            guard tracker.containsCTLActions else {
                mainTDSTrackers[key] = tracker
                continue
            }

            // if we found some CTL rules, split out into its own list
            if let rules = tracker.rules as [KnownTracker.Rule]? {
                var mainRules: [KnownTracker.Rule] = []
                var ctlRules: [KnownTracker.Rule] = []

                for rule in rules.reversed() {
                    if let action = rule.action, action == .blockCTLFB {
                        ctlRules.insert(rule, at: 0)
                    } else {
                        ctlRules.insert(rule, at: 0)
                        mainRules.insert(rule, at: 0)
                    }
                }

                let mainTracker = KnownTracker(domain: tracker.domain,
                                               defaultAction: tracker.defaultAction,
                                               owner: tracker.owner,
                                               prevalence: tracker.prevalence,
                                               subdomains: tracker.subdomains,
                                               categories: tracker.categories,
                                               rules: mainRules)
                let ctlTracker = KnownTracker(domain: tracker.domain,
                                              defaultAction: tracker.defaultAction,
                                              owner: tracker.owner,
                                              prevalence: tracker.prevalence,
                                              subdomains: tracker.subdomains,
                                              categories: tracker.categories,
                                              rules: ctlRules)
                mainTDSTrackers[key] = mainTracker
                ctlTrackers[key] = ctlTracker
            }
        }

        return (mainTDSTrackers, ctlTrackers)
    }

    private func extractDomains(from entities: [String: Entity]) -> [String: String] {
        var domains = [String: String]()
        for entity in entities {
            for domain in entity.value.domains ?? [] {
                domains[domain] = entity.key
            }
        }
        return domains
    }

}

private extension TrackerData {

    func extractEntities(for trackers: [String: KnownTracker]) -> [String: Entity] {
        let trackerOwners = Set(trackers.values.compactMap { $0.owner?.name })
        let entities = entities.filter { trackerOwners.contains($0.key) }
        return entities
    }

}

private extension KnownTracker {

    var containsCTLActions: Bool {
        if let rules = rules {
            for rule in rules {
                if let action = rule.action, action == .blockCTLFB {
                    return true
                }
            }
        }
        return false
    }

}

// Remove the above after moving splitter to BSK
// ---------

struct CTLTests: Decodable {

    struct Test: Decodable {

        let description: String
        let site: String
        let request: String
        let ctlEnabled: Bool
        let isRequestLoaded: Bool

        init(description: String, site: String, request: String, ctlEnabled: Bool, isRequestLoaded: Bool) {
            self.description = description
            self.site = site
            self.request = request
            self.ctlEnabled = ctlEnabled
            self.isRequestLoaded = isRequestLoaded
        }

    }

    static let exampleRules = """
{
  "trackers": {
        "facebook.net": {
            "domain": "facebook.net",
            "owner": {
                "name": "Facebook, Inc.",
                "displayName": "Facebook",
                "privacyPolicy": "https://www.facebook.com/privacy/explanation",
                "url": "https://facebook.com"
            },
            "prevalence": 0.268,
            "fingerprinting": 2,
            "cookies": 0.208,
            "categories": [],
            "default": "ignore",
            "rules": [
                {
                    "rule": "facebook\\\\.net/.*/all\\\\.js",
                    "surrogate": "fb-sdk.js",
                    "action": "block-ctl-fb",
                    "fingerprinting": 1,
                    "cookies": 0.0000408
                },
                {
                    "rule": "facebook\\\\.net/.*/fbevents\\\\.js",
                    "fingerprinting": 1,
                    "cookies": 0.108
                },
                {
                    "rule": "facebook\\\\.net/[a-z_A-Z]+/sdk\\\\.js",
                    "surrogate": "fb-sdk.js",
                    "action": "block-ctl-fb",
                    "fingerprinting": 1,
                    "cookies": 0.000334
                },
                {
                    "rule": "facebook\\\\.net/signals/config/",
                    "fingerprinting": 1,
                    "cookies": 0.000101
                },
                {
                    "rule": "facebook\\\\.net\\\\/signals\\\\/plugins\\\\/openbridge3\\\\.js",
                    "fingerprinting": 1,
                    "cookies": 0
                },
                {
                    "rule": "facebook\\\\.net/.*/sdk/.*customerchat\\\\.js",
                    "fingerprinting": 1,
                    "cookies": 0.00000681
                },
                {
                    "rule": "facebook\\\\.net\\\\/en_US\\\\/messenger\\\\.Extensions\\\\.js",
                    "fingerprinting": 1,
                    "cookies": 0
                },
                {
                    "rule": "facebook\\\\.net\\\\/en_US\\\\/sdk\\\\/xfbml\\\\.save\\\\.js",
                    "fingerprinting": 1,
                    "cookies": 0
                },
                {
                    "rule": "facebook\\\\.net/",
                    "action": "block-ctl-fb"
                }
                ]
        }
  },
  "entities": {
    "Facebook, Inc.": {
      "domains": [
        "facebook.net"
      ],
      "displayName": "Facebook",
      "prevalence": 0.1
    }
  },
  "domains": {
    "facebook.net": "Facebook, Inc."
  }
}
"""

    static let domainTests: [CTLTests.Test] = [
        CTLTests.Test(description: "Basic blocking - tracker request",
                      site: "https://www.example.com",
                      request: "https://www.facebook.net/signals/config/config.js",
                      ctlEnabled: false,
                      isRequestLoaded: false),
        CTLTests.Test(description: "Basic blocking - ctl request",
                      site: "https://www.example.com",
                      request: "https://www.facebook.net/some.js",
                      ctlEnabled: false,
                      isRequestLoaded: false)
    ]
}

class CTLReferenceTests: XCTestCase {

    let schemeHandler = TestSchemeHandler()
    let userScriptDelegateMock = MockRulesUserScriptDelegate()
    let navigationDelegateMock = MockNavigationDelegate()
    let tld = TLD()

    var webView: WKWebView!
    var tds: TrackerData!
    var tests = CTLTests.domainTests
    var mockWebsite: MockWebsite!

    var compiledCTLRules: WKContentRuleList!

    func setupWebView(trackerData: TrackerData,
                      ctlTrackerData: TrackerData?,
                      userScriptDelegate: ContentBlockerRulesUserScriptDelegate,
                      schemeHandler: TestSchemeHandler,
                      completion: @escaping (WKWebView) -> Void) {

        WebKitTestHelper.prepareContentBlockingRules(trackerData: trackerData,
                                                     exceptions: [],
                                                     tempUnprotected: [],
                                                     trackerExceptions: []) { fullRules in

            guard let fullRules = fullRules else {
                XCTFail("Rules were not compiled properly")
                return
            }

            WebKitTestHelper.prepareContentBlockingRules(trackerData: trackerData,
                                                         exceptions: [],
                                                         tempUnprotected: [],
                                                         trackerExceptions: []) { ctlRules in

                guard let ctlRules = ctlRules else {
                    XCTFail("Rules were not compiled properly")
                    return
                }

                self.compiledCTLRules = ctlRules

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

                let config = TestSchemeContentBlockerUserScriptConfig(privacyConfiguration: privacyConfig,
                                                                      trackerData: trackerData,
                                                                      ctlTrackerData: ctlTrackerData,
                                                                      tld: self.tld)

                let userScript = ContentBlockerRulesUserScript(configuration: config)
                userScript.delegate = userScriptDelegate

                for messageName in userScript.messageNames {
                    configuration.userContentController.add(userScript, name: messageName)
                }

                configuration.userContentController.addUserScript(WKUserScript(source: userScript.source,
                                                                               injectionTime: .atDocumentStart,
                                                                               forMainFrameOnly: false))
                configuration.userContentController.add(fullRules)

                completion(webView)
            }
        }
    }

    func filterFBTracker(from tds: TrackerData) -> TrackerData {

        guard let fbTracker = tds.trackers["facebook.net"] else {
            XCTFail("Missing FB tracker")
            return TrackerData(trackers: [:], entities: [:], domains: [:], cnames: [:])
        }

        return TrackerData(trackers: ["facebook.net" : fbTracker],
                           entities: tds.entities,
                           domains: tds.domains,
                           cnames: [:])
    }

    func testDomainAllowlist() throws {

        let fullTDS = CTLTests.exampleRules.data(using: .utf8)!
        let fullTrackerData = (try? JSONDecoder().decode(TrackerData.self, from: fullTDS))!

        let dataSet = TrackerDataManager.DataSet(tds: fullTrackerData, etag: UUID().uuidString)
        let ruleList = ContentBlockerRulesList(name: "test",
                                               trackerData: nil,
                                               fallbackTrackerData: dataSet)
        let ctlSplitter = LocalClickToLoadRulesSplitter(rulesList: ruleList)

        guard let splitRules = ctlSplitter.split() else {
            XCTFail("Could not split rules")
            return
        }

        tests = CTLTests.domainTests

        let testsExecuted = expectation(description: "tests executed")
        testsExecuted.expectedFulfillmentCount = tests.count

        setupWebView(trackerData: splitRules.withoutBlockCTL.fallbackTrackerData.tds,
                     ctlTrackerData: splitRules.withBlockCTL.fallbackTrackerData.tds,
                     userScriptDelegate: userScriptDelegateMock,
                     schemeHandler: schemeHandler) { webView in
            self.webView = webView

            self.popTestAndExecute(onTestExecuted: testsExecuted)
        }

        waitForExpectations(timeout: 30, handler: nil)
    }

    // swiftlint:disable function_body_length
    private func popTestAndExecute(onTestExecuted: XCTestExpectation) {

        guard let test = tests.popLast() else {
            return
        }

        os_log("TEST: %s", test.description)

        var siteURL = URL(string: test.site.testSchemeNormalized)!
        if siteURL.absoluteString.hasSuffix(".com") {
            siteURL = siteURL.appendingPathComponent("index.html")
        }
        let requestURL = URL(string: test.request.testSchemeNormalized)!

        let resource = MockWebsite.EmbeddedResource(type: .script,
                                                    url: requestURL)

        mockWebsite = MockWebsite(resources: [resource])

        schemeHandler.reset()
        schemeHandler.requestHandlers[siteURL] = { _ in
            return self.mockWebsite.htmlRepresentation.data(using: .utf8)!
        }

        userScriptDelegateMock.reset()

        os_log("Loading %s ...", siteURL.absoluteString)
        let request = URLRequest(url: siteURL)

        WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeDiskCache,
                                                          WKWebsiteDataTypeMemoryCache,
                                                          WKWebsiteDataTypeOfflineWebApplicationCache],
                                                modifiedSince: Date(timeIntervalSince1970: 0),
                                                completionHandler: {
            self.webView.load(request)
        })

        navigationDelegateMock.onDidFinishNavigation = {
            os_log("Website loaded")
            if !test.isRequestLoaded {
                // Only website request
                XCTAssertEqual(self.schemeHandler.handledRequests.count, 1)
                // Only resource request
                XCTAssertEqual(self.userScriptDelegateMock.detectedTrackers.count, 1)

                if let tracker = self.userScriptDelegateMock.detectedTrackers.first {
                    XCTAssert(tracker.isBlocked)
                } else {
                    XCTFail("Expected to detect tracker for test \(test.description)")
                }
            } else {
                // Website request & resource request
                XCTAssertEqual(self.schemeHandler.handledRequests.count, 2)

                if let pageEntity = self.tds.findEntity(forHost: siteURL.host!),
                   let trackerOwner = self.tds.findTracker(forUrl: requestURL.absoluteString)?.owner,
                   pageEntity.displayName == trackerOwner.name {

                    // Nothing to detect - tracker and website have the same entity
                } else {
                    XCTAssertEqual(self.userScriptDelegateMock.detectedTrackers.count, 1)

                    if let tracker = self.userScriptDelegateMock.detectedTrackers.first {
                        XCTAssertFalse(tracker.isBlocked)
                    } else {
                        XCTFail("Expected to detect tracker for test \(test.description)")
                    }
                }
            }

            onTestExecuted.fulfill()
            DispatchQueue.main.async {
                self.popTestAndExecute(onTestExecuted: onTestExecuted)
            }
        }
    }
    // swiftlint:enable function_body_length

}
