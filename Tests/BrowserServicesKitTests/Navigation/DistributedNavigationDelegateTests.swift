//
//  DistributedNavigationDelegateTests.swift
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
import WebKit
@testable import BrowserServicesKit

func expect(_ description: String, _ file: StaticString = #file, _ line: UInt = #line) -> XCTestExpectation {
    XCTestExpectation(description: description)
}

@available(macOS 12.0, *)
final class DistributedNavigationDelegateTests: XCTestCase {

    let navigationDelegate = DistributedNavigationDelegate(logger: .default)
    var testSchemeHandler: TestNavigationSchemeHandler! = TestNavigationSchemeHandler()
    lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(testSchemeHandler, forURLScheme: TestNavigationSchemeHandler.scheme)
        return WKWebView(frame: .zero, configuration: configuration)
    }()
    static let httpsURL = URL(string: "https://duckduckgo.com/")!
    static let testSchemeURL = URL(string: TestNavigationSchemeHandler.scheme + "://duckduckgo.com")!
    static let redirectSchemeURL = URL(string: TestNavigationSchemeHandler.scheme + "://redirect-1.com/")!
    static let redirectSchemeURL2 = URL(string: TestNavigationSchemeHandler.scheme + "://redirect2.com")!
    let httpsRequest = URLRequest(url: DistributedNavigationDelegateTests.httpsURL)
    let testSchemeRequest = URLRequest(url: DistributedNavigationDelegateTests.testSchemeURL)
    let redirectSchemeRequest = URLRequest(url: DistributedNavigationDelegateTests.redirectSchemeURL)
    let redirectSchemeRequest2 = URLRequest(url: DistributedNavigationDelegateTests.redirectSchemeURL2)
    let responseData = Data()
    func clientRedirectData(to url: URL) -> Data {
        """
        <html><body>
        <script language='JavaScript'>
            window.parent.location.replace("\(url.absoluteString)");
        </script>
        </body></html>
        """.data(using: .utf8)!
    }

    override func setUp() {
        webView.navigationDelegate = navigationDelegate
    }
    override func tearDown() {
        self.testSchemeHandler = nil
    }

    func responder(at index: Int) -> NavigationResponderMock! {
        navigationDelegate.responders[index] as? NavigationResponderMock
    }

    private func assertHistoryEquals(_ lhs: [NavigationEvent],
                                     _ rhs: [NavigationEvent],
                                     file: StaticString = #file,
                                     line: UInt = #line) {
        for idx in 0..<max(lhs.count, rhs.count) {
            let event1 = lhs.indices.contains(idx) ? lhs[idx] : nil
            let event2 = rhs.indices.contains(idx) ? rhs[idx] : nil
            if event1 != event2 {
                XCTAssertEqual(event1, event2, file: file, line: line)
            }
        }
    }

    // MARK: - Tests

    func testRegularNavigationResponderChain() {
        navigationDelegate.setResponders(
            .strong(NavigationResponderMock()),
            .strong(NavigationResponderMock()),
            .strong(NavigationResponderMock())
        )

        // Regular navigation without redirects
        // 1st: .next
        responder(at: 0).onNavigationAction = { _, _ in .next }
        // 2nd: .allow
        responder(at: 1).onNavigationAction = { _, _ in .allow }
        // 3rd: not called
        responder(at: 2).onNavigationAction = { _, _ in XCTFail(); return .cancel }

        let expectedNavAction = NavAction(navigationType: .unknown, url: Self.testSchemeURL, sourceFrameIsMain: true, targetFrameIsMain: true)
        let expectedFor2: [NavigationEvent] = [
            .willStart(expectedNavAction),
            .didStart(.init(navigationAction: expectedNavAction, state: .started)),
            .navigationResponse(.init(isForMainFrame: true, url: Self.testSchemeURL)),
            .didCommit(.init(navigationAction: expectedNavAction, state: .responseReceived(Self.testSchemeURL), isCommitted: true)),
            .willFinish(.init(navigationAction: expectedNavAction, state: .awaitingFinishOrClientRedirect, isCommitted: true)),
            .didFinish(.init(navigationAction: expectedNavAction, state: .finished, isCommitted: true)),
        ]
        let expectedFor0and1 = [.navigationAction(expectedNavAction)] + expectedFor2

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 2).onDidFinish = { _ in eDidFinish.fulfill() }

        testSchemeHandler.onRequest = { [responseData] task in
            task.didReceive(.response(for: task.request))
            task.didReceive(responseData)
            task.didFinish()
        }

        webView.load(testSchemeRequest)
        waitForExpectations(timeout: 1)

        assertHistoryEquals(responder(at: 0).history, expectedFor0and1)
        assertHistoryEquals(responder(at: 1).history, expectedFor0and1)
        assertHistoryEquals(responder(at: 2).history, expectedFor2)
    }

    func testFailingNavigationResponderChain() {
        navigationDelegate.setResponders(
            .strong(NavigationResponderMock()),
            .strong(NavigationResponderMock()),
            .strong(NavigationResponderMock())
        )

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 2).onDidFinish = { _ in eDidFinish.fulfill() }

        webView.loadSimulatedRequest(httpsRequest, responseHTML: "")
        waitForExpectations(timeout: 1)
    }

    func testWhenResponderCancelsNavigation_followingRespondersNotCalled() {
        navigationDelegate.setResponders(
            .strong(NavigationResponderMock()),
            .strong(NavigationResponderMock()),
            .strong(NavigationResponderMock())
        )

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 2).onDidFinish = { _ in eDidFinish.fulfill() }

        webView.loadSimulatedRequest(httpsRequest, responseHTML: "")
        waitForExpectations(timeout: 1)
    }

    func testServerRedirect() {
        navigationDelegate.setResponders(.strong(NavigationResponderMock()))
        responder(at: 0).onNavigationAction = { _, _  in .allow }

        let expectedNavAction = NavAction(navigationType: .unknown, url: Self.testSchemeURL)
        let redirectedNavigation = EquatableNav(navigationAction: expectedNavAction, state: .redirected, isCommitted: false)
        let redirectNavAction = NavAction(navigationType: .redirect(type: .server, previousNavigation: redirectedNavigation), url: Self.redirectSchemeURL)
        let expectedEvents: [NavigationEvent] = [
            .navigationAction(expectedNavAction),
            .willStart(expectedNavAction),
            .didStart(.init(navigationAction: expectedNavAction, state: .started)),
            .navigationAction(redirectNavAction),
            .willStart(redirectNavAction),
            .navigationResponse(.init(isForMainFrame: true, url: Self.redirectSchemeURL)),
            .didCommit(.init(navigationAction: redirectNavAction, state: .responseReceived(Self.redirectSchemeURL), isCommitted: true)),
            .willFinish(.init(navigationAction: redirectNavAction, state: .awaitingFinishOrClientRedirect, isCommitted: true)),
            .didFinish(.init(navigationAction: redirectNavAction, state: .finished, isCommitted: true)),
        ]

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        testSchemeHandler.onRequest = { [unowned self, responseData] task in
            task.willPerformRedirection(.response(for: task.request), newRequest: self.redirectSchemeRequest) { request in
                task.didReceive(.response(for: self.redirectSchemeRequest))
                task.didReceive(responseData)
                task.didFinish()
            }
        }

        webView.load(testSchemeRequest)
        waitForExpectations(timeout: 1)

        assertHistoryEquals(responder(at: 0).history, expectedEvents)
    }

    func testDoubleServerRedirect() {
        navigationDelegate.setResponders(.strong(NavigationResponderMock()))
        responder(at: 0).onNavigationAction = { _, _  in .allow }

        let expectedNavAction = NavAction(navigationType: .unknown, url: Self.testSchemeURL)
        let redirectedNavigation = EquatableNav(navigationAction: expectedNavAction, state: .redirected, isCommitted: false)
        let redirectNavAction = NavAction(navigationType: .redirect(type: .server, previousNavigation: redirectedNavigation), url: Self.redirectSchemeURL)
        let redirectedNavigation2 = EquatableNav(navigationAction: redirectNavAction, state: .redirected, isCommitted: false)
        let redirectNavAction2 = NavAction(navigationType: .redirect(type: .server, previousNavigation: redirectedNavigation2), url: Self.redirectSchemeURL2)
        let expectedEvents: [NavigationEvent] = [
            .navigationAction(expectedNavAction),
            .willStart(expectedNavAction),
            .didStart(.init(navigationAction: expectedNavAction, state: .started)),
            .navigationAction(redirectNavAction),
            .willStart(redirectNavAction),
            .navigationAction(redirectNavAction2),
            .willStart(redirectNavAction2),
            .navigationResponse(.init(isForMainFrame: true, url: Self.redirectSchemeURL2)),
            .didCommit(.init(navigationAction: redirectNavAction2, state: .responseReceived(Self.redirectSchemeURL2), isCommitted: true)),
            .willFinish(.init(navigationAction: redirectNavAction2, state: .awaitingFinishOrClientRedirect, isCommitted: true)),
            .didFinish(.init(navigationAction: redirectNavAction2, state: .finished, isCommitted: true)),
        ]

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        testSchemeHandler.onRequest = { [unowned self, responseData] task in
            task.willPerformRedirection(.response(for: task.request), newRequest: self.redirectSchemeRequest) { request in
                task.willPerformRedirection(.response(for: request), newRequest: self.redirectSchemeRequest2) { request in
                    task.didReceive(.response(for: self.redirectSchemeRequest2))
                    task.didReceive(responseData)
                    task.didFinish()
                }
            }
        }

        webView.load(testSchemeRequest)
        waitForExpectations(timeout: 1)

        assertHistoryEquals(responder(at: 0).history, expectedEvents)
    }

    func testClientRedirect() {
        navigationDelegate.setResponders(.strong(NavigationResponderMock()))

        let expectedNavAction = NavAction(navigationType: .unknown, url: Self.testSchemeURL)
        let redirectedNavigation = EquatableNav(navigationAction: expectedNavAction, state: .redirected, isCommitted: true)
        let redirectNavAction = NavAction(navigationType: .redirect(type: .client(delay: 0), previousNavigation: redirectedNavigation), url: Self.redirectSchemeURL)
        let finalNavigation = EquatableNav(navigationAction: redirectNavAction, state: .started)
        let expectedEvents: [NavigationEvent] = [
            .navigationAction(expectedNavAction),
            .willStart(expectedNavAction),
            .didStart(.init(navigationAction: expectedNavAction, state: .started)),
            .navigationResponse(.init(isForMainFrame: true, url: Self.testSchemeURL)),
            .didCommit(.init(navigationAction: expectedNavAction, state: .responseReceived(Self.testSchemeURL), isCommitted: true)),
            .willFinish(.init(navigationAction: expectedNavAction, state: .awaitingRedirect(type: .client(delay: 0), url: Self.redirectSchemeURL), isCommitted: true)),
            .navigationAction(redirectNavAction),
            .willStart(redirectNavAction),
            .didStart(finalNavigation),
            .navigationResponse(.init(isForMainFrame: true, url: Self.redirectSchemeURL)),
            .didCommit(.init(navigationAction: redirectNavAction, state: .responseReceived(Self.redirectSchemeURL), isCommitted: true)),
            .willFinish(.init(navigationAction: redirectNavAction, state: .awaitingFinishOrClientRedirect, isCommitted: true)),
            .didFinish(.init(navigationAction: redirectNavAction, state: .finished, isCommitted: true)),
        ]

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        testSchemeHandler.onRequest = { [unowned self] task in
            task.didReceive(.response(for: task.request))
            if task.request.url == Self.testSchemeURL {
                task.didReceive(self.clientRedirectData(to: Self.redirectSchemeURL))
            } else {
                task.didReceive(self.responseData)
            }
            task.didFinish()
        }

        webView.load(testSchemeRequest)
        waitForExpectations(timeout: 1)

        assertHistoryEquals(responder(at: 0).history, expectedEvents)
    }

    func testClientRedirectWithoutWillPerformClientRedirect() {
        let handler = WillPerformClientRedirectHandler()
        navigationDelegate.registerCustomDelegateMethodHandler(.strong(handler), for: #selector(WillPerformClientRedirectHandler.webView(_:willPerformClientRedirectTo:delay:)))

        let eWillPerformClientRedirect = expectation(description: "willPerformClientRedirect")
        handler.willPerformClientRedirectHandler = { _, _ in
            eWillPerformClientRedirect.fulfill()
        }

        navigationDelegate.setResponders(.strong(NavigationResponderMock()))

        let expectedNavAction = NavAction(navigationType: .unknown, url: Self.testSchemeURL)
        let redirectedNavigation = EquatableNav(navigationAction: expectedNavAction, state: .redirected, isCommitted: true)
        let redirectNavAction = NavAction(navigationType: .redirect(type: .client(delay: 0), previousNavigation: redirectedNavigation), url: Self.redirectSchemeURL)
        let finalNavigation = EquatableNav(navigationAction: redirectNavAction, state: .started)
        let expectedEvents: [NavigationEvent] = [
            .navigationAction(expectedNavAction),
            .willStart(expectedNavAction),
            .didStart(.init(navigationAction: expectedNavAction, state: .started)),
            .navigationResponse(.init(isForMainFrame: true, url: Self.testSchemeURL)),
            .didCommit(.init(navigationAction: expectedNavAction, state: .responseReceived(Self.testSchemeURL), isCommitted: true)),
            .willFinish(.init(navigationAction: expectedNavAction, state: .awaitingFinishOrClientRedirect, isCommitted: true)),
            .navigationAction(redirectNavAction),
            .willStart(redirectNavAction),
            .didStart(finalNavigation),
            .navigationResponse(.init(isForMainFrame: true, url: Self.redirectSchemeURL)),
            .didCommit(.init(navigationAction: redirectNavAction, state: .responseReceived(Self.redirectSchemeURL), isCommitted: true)),
            .willFinish(.init(navigationAction: redirectNavAction, state: .awaitingFinishOrClientRedirect, isCommitted: true)),
            .didFinish(.init(navigationAction: redirectNavAction, state: .finished, isCommitted: true)),
        ]

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
        }

        testSchemeHandler.onRequest = { [unowned self] task in
            task.didReceive(.response(for: task.request))
            if task.request.url == Self.testSchemeURL {
                task.didReceive(self.clientRedirectData(to: Self.redirectSchemeURL))
            } else {
                task.didReceive(self.responseData)
            }
            task.didFinish()
        }

        webView.load(testSchemeRequest)
        waitForExpectations(timeout: 1)

        assertHistoryEquals(responder(at: 0).history, expectedEvents)
    }

    func testDoubleClientRedirect() {}
    func testClientRedirectWithFakeBackAction() {}
    func testClientAndServerRedirect() {}
    func testDoubleServerAndClientRedirect() {}

}

private final class WillPerformClientRedirectHandler: NSObject, NavigationResponder {
    var willPerformClientRedirectHandler: ((URL, TimeInterval) -> Void)?
    @objc(_webView:willPerformClientRedirectToURL:delay:)
    func webView(_ webView: WKWebView, willPerformClientRedirectTo url: URL, delay: TimeInterval) {
        self.willPerformClientRedirectHandler?(url, delay)
    }
}

private extension URLResponse {
    static func response(for request: URLRequest, mimeType: String? = "text/html", expectedLength: Int = 0, encoding: String? = nil) -> URLResponse {
        return URLResponse(url: request.url!, mimeType: mimeType, expectedContentLength: expectedLength, textEncodingName: encoding)
    }
}
