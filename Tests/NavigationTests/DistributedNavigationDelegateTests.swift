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

import Common
import Swifter
import WebKit
import XCTest
@testable import Navigation

func expect(_ description: String, _ file: StaticString = #file, _ line: UInt = #line) -> XCTestExpectation {
    XCTestExpectation(description: description)
}

@available(macOS 12.0, *)
final class DistributedNavigationDelegateTests: XCTestCase {

    let navigationDelegateProxy = NavigationDelegateProxy(delegate: DistributedNavigationDelegate(logger: .default))
    var navigationDelegate: DistributedNavigationDelegate { navigationDelegateProxy.delegate }
    var testSchemeHandler: TestNavigationSchemeHandler! = TestNavigationSchemeHandler()
    let server = HttpServer()

    lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(testSchemeHandler, forURLScheme: TestNavigationSchemeHandler.scheme)
        return WKWebView(frame: .zero, configuration: configuration)
    }()

    struct URLs {
        let https = URL(string: "https://duckduckgo.com/")!

        let testScheme = URL(string: TestNavigationSchemeHandler.scheme + "://duckduckgo.com")!

        let local = URL(string: "http://localhost:8084")!
        let local1 = URL(string: "http://localhost:8084/1")!
        let local2 = URL(string: "http://localhost:8084/2")!
        let local3 = URL(string: "http://localhost:8084/3")!
        let local4 = URL(string: "http://localhost:8084/4")!

        let aboutBlank = URL(string: "about:blank")!
        let aboutPrefs = URL(string: "about:prefs")!

        let post3 = URL(string: "http://localhost:8084/post3.html")!
    }
    let urls = URLs()

    struct DataSource {
        let empty = Data()
        let html = "<html />".data(using: .utf8)!
        let htmlWithIframe3 = "<html><body><iframe src='/3' /></body></html>".data(using: .utf8)!
        let metaRedirect = """
        <html>
            <head>
            <meta http-equiv="Refresh" content="0; URL=http://localhost:8084/3" />
            </head>
        </html>
        """.data(using: .utf8)!

        func clientRedirectData(with url: URL) -> Data {
            """
                <html><body>
                <script language='JavaScript'>
                    window.parent.location.replace("\(url.absoluteString)");
                </script>
                </body></html>
            """.data(using: .utf8)!
        }

        let aboutPrefsInteractionStateData = Data([0x00, 0x00, 0x00, 0x02]) + """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            <key>IsAppInitiated</key>
            <true/>
            <key>RenderTreeSize</key>
            <integer>3</integer>
            <key>SessionHistory</key>
            <dict>
            <key>SessionHistoryCurrentIndex</key>
            <integer>0</integer>
            <key>SessionHistoryEntries</key>
            <array>
                <dict>
                    <key>SessionHistoryEntryData</key>
                    <data>
                    AAAAAAAAAAACAAAAAAAAAAAAAAAAAAAAeLI8QbDyBQAA
                    AAAAAAAAAP////8AAAAAd7I8QbDyBQD/////AAAAAAAA
                    AAAAAAAAAAAAAP////8=
                    </data>
                    <key>SessionHistoryEntryOriginalURL</key>
                    <string>about:prefs</string>
                    <key>SessionHistoryEntryShouldOpenExternalURLsPolicyKey</key>
                    <integer>1</integer>
                    <key>SessionHistoryEntryTitle</key>
                    <string></string>
                    <key>SessionHistoryEntryURL</key>
                    <string>about:prefs</string>
                </dict>
            </array>
            <key>SessionHistoryVersion</key>
            <integer>1</integer>
            </dict>
            </dict>
            </plist>
        """.data(using: .utf8)!

        let aboutPrefsAfterRegularNavigationInteractionStateData = Data([0x00, 0x00, 0x00, 0x02]) + """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            <key>IsAppInitiated</key>
            <true/>
            <key>RenderTreeSize</key>
            <integer>3</integer>
            <key>SessionHistory</key>
            <dict>
            <key>SessionHistoryCurrentIndex</key>
            <integer>1</integer>
            <key>SessionHistoryEntries</key>
            <array>
                <dict>
                    <key>SessionHistoryEntryData</key>
                    <data>
                    AAAAAAAAAAACAAAAAAAAAAAAAAAAAAAARIMiXLDyBQAA
                    AAAAAAAAAP////8AAAAAQ4MiXLDyBQD/////AAAAAAAA
                    AAAAAIA/AAAAAP////8=
                    </data>
                    <key>SessionHistoryEntryOriginalURL</key>
                    <string>http://localhost:8084/</string>
                    <key>SessionHistoryEntryShouldOpenExternalURLsPolicyKey</key>
                    <integer>1</integer>
                    <key>SessionHistoryEntryTitle</key>
                    <string></string>
                    <key>SessionHistoryEntryURL</key>
                    <string>http://localhost:8084/</string>
                </dict>
                <dict>
                    <key>SessionHistoryEntryData</key>
                    <data>
                    AAAAAAAAAAACAAAAAAAAAAAAAAAAAAAARoMiXLDyBQAA
                    AAAAAAAAAP////8AAAAARYMiXLDyBQD/////AAAAAAAA
                    AAAAAAAAAAAAAP////8=
                    </data>
                    <key>SessionHistoryEntryOriginalURL</key>
                    <string>about:blank</string>
                    <key>SessionHistoryEntryShouldOpenExternalURLsPolicyKey</key>
                    <integer>1</integer>
                    <key>SessionHistoryEntryTitle</key>
                    <string></string>
                    <key>SessionHistoryEntryURL</key>
                    <string>about:blank</string>
                </dict>
            </array>
            <key>SessionHistoryVersion</key>
            <integer>1</integer>
            </dict>
            </dict>
            </plist>
        """.data(using: .utf8)!

        let interactionStateData = Data([0x00, 0x00, 0x00, 0x02]) + """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            <key>IsAppInitiated</key>
            <true/>
            <key>RenderTreeSize</key>
            <integer>7</integer>
            <key>SessionHistory</key>
            <dict>
            <key>SessionHistoryCurrentIndex</key>
            <integer>1</integer>
            <key>SessionHistoryEntries</key>
            <array>
                <dict>
                    <key>SessionHistoryEntryData</key>
                    <data>
                    AAAAAAAAAAACAAAAAAAAAAAAAAAAAAAAqehUL2XwBQAA
                    AAAAAAAAAP////8AAAAAqOhUL2XwBQD/////AAAAAAAA
                    AAAAAIA/AAAAAP////8=
                    </data>
                    <key>SessionHistoryEntryOriginalURL</key>
                    <string>http://localhost:8084/1</string>
                    <key>SessionHistoryEntryShouldOpenExternalURLsPolicyKey</key>
                    <integer>1</integer>
                    <key>SessionHistoryEntryTitle</key>
                    <string></string>
                    <key>SessionHistoryEntryURL</key>
                    <string>http://localhost:8084/1</string>
                </dict>
                <dict>
                    <key>SessionHistoryEntryData</key>
                    <data>
                    AAAAAAAAAAACAAAAAAAAAAAAAAAAAAAAq+hUL2XwBQAA
                    AAAAAAAAAP////8AAAAAquhUL2XwBQD/////AAAAAAAA
                    AAAAAAAAAAAAAP////8=
                    </data>
                    <key>SessionHistoryEntryOriginalURL</key>
                    <string>http://localhost:8084/</string>
                    <key>SessionHistoryEntryShouldOpenExternalURLsPolicyKey</key>
                    <integer>1</integer>
                    <key>SessionHistoryEntryTitle</key>
                    <string></string>
                    <key>SessionHistoryEntryURL</key>
                    <string>http://localhost:8084/</string>
                </dict>
            </array>
            <key>SessionHistoryVersion</key>
            <integer>1</integer>
            </dict>
            </dict>
            </plist>
        """.data(using: .utf8)!
    }
    let data = DataSource()

    override func setUp() {
        webView.navigationDelegate = navigationDelegateProxy
    }

    override func tearDown() {
        self.testSchemeHandler = nil
        server.stop()
        self.navigationDelegate.setResponders()
    }

    func responder(at index: Int) -> NavigationResponderMock! {
        navigationDelegate.responders[index] as? NavigationResponderMock
    }

    func cached(_ idx: Int) -> NavAction {
        if responder(at: 0).navigationActionsCache.isEmpty {
            _=encodedResponderHistory(at: 0)
        }
        return responder(at: 0).navigationActionsCache[idx]
    }

    // MARK: FrameInfo mocking

    func main(_ current: URL = .empty, secOrigin: SecurityOrigin? = nil) -> FrameInfo {
        FrameInfo(frameIdentity: .mainFrameIdentity(for: webView), url: current, securityOrigin: secOrigin ?? current.securityOrigin)
    }

    func frame(_ handle: Int, _ url: URL, secOrigin: SecurityOrigin? = nil) -> FrameInfo {
        FrameInfo(frameIdentity: FrameIdentity(handle: "\(handle)", webViewIdentity: .init(nonretainedObject: webView), isMainFrame: false), url: url, securityOrigin: secOrigin ?? url.securityOrigin)
    }
    func frame(_ handle: Int, _ url: String, secOrigin: SecurityOrigin? = nil) -> FrameInfo {
        frame(handle, URL(string: url)!, secOrigin: secOrigin)
    }

    // Event sequence checking
    private func assertHistory(ofResponderAt responderIdx: Int, equalsTo rhs: [NavigationEvent],
                               file: StaticString = #file,
                               line: UInt = #line) {
        let lhs = responder(at: responderIdx).history
        for idx in 0..<max(lhs.count, rhs.count) {
            let event1 = lhs.indices.contains(idx) ? lhs[idx] : nil
            let event2 = rhs.indices.contains(idx) ? rhs[idx] : nil
            if event1 != event2 {
                printEncoded(responder: responderIdx)

                if case .navigationAction(let r1, _) = event1, case .navigationAction(let r2, _) = event2 {
                    if r1.navigationAction.request.allHTTPHeaderFields != r2.navigationAction.request.allHTTPHeaderFields {
                        let (k, v) = r1.navigationAction.request.allHTTPHeaderFields!.first(where: { r2.navigationAction.request.allHTTPHeaderFields![$0.0] != $0.1 })!
                        XCTFail("\nk: \(k): \"\(v)\" not equal to \(r2.navigationAction.request.allHTTPHeaderFields![k].map { "\"" + String(describing: $0) + "\"" } ?? "<nil>")", file: file, line: line)
                    } else {
                        print(r1)
                        print(r2)
                    }
                } else if case .didReceiveRedirect(let h1) = event1, case .didReceiveRedirect(let h2) = event2 {
                    print(h1)
                    print(h2)
                }
                XCTFail("\n\(event1 != nil ? "\(event1!)" : "<nil>")\n not equal to" +
                        "\n\(event2 != nil ? "\(event2!)" : "<nil>")",
                        file: file, line: line)
            }
        }
    }

    private func assertHistory(ofResponderAt responderIdx: Int, equalsToHistoryOfResponderAt responderIdx2: Int,
                               file: StaticString = #file,
                               line: UInt = #line) {
        assertHistory(ofResponderAt: responderIdx, equalsTo: responder(at: responderIdx2).history)
    }

    func encodedResponderHistory(at idx: Int = 0) -> String {
        responder(at: idx).history.encoded(with: urls, webView: webView, dataSource: data,
                                           navigationActions: &responder(at: 0 /* responder #0 has all nav actions */).navigationActionsCache)
    }

    func printEncoded(responder idx: Int = 0) {
        print("Responder #\(idx) history encoded:")
        print(encodedResponderHistory(at: idx))
    }

    // MARK: - The Tests

    func testWhenNavigationFinished_didFinishIsCalled() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        server.middleware = [{ request in
            return .ok(.data(self.data.html))
        }]

        // regular navigation from an empty state
        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .response(Nav(action: cached(0), .resp(urls.local, data.html.count))),
            .didCommit(Nav(action: cached(0), .resp(urls.local, data.html.count), .committed)),
            .didFinish(Nav(action: cached(0), .finished, .committed))
        ])
    }

    func testWhenResponderCancelsNavigationAction_followingRespondersNotCalled() {
        navigationDelegate.setResponders(
            .strong(NavigationResponderMock()),
            .strong(NavigationResponderMock()),
            .strong(NavigationResponderMock())
        )

        responder(at: 0).onNavigationAction = { _, _ in .next }
        responder(at: 1).onNavigationAction = { _, _ in .cancel(with: .redirect(req(self.urls.local2))) }
        responder(at: 2).onNavigationAction = { _, _ in XCTFail("Unexpected decidePolicyForNavigationAction:"); return .next }

        for i in 0..<3 {
            let eWillCancel = expectation(description: "onWillFinish")
            let eDidCancel = expectation(description: "onDidFinish")
            responder(at: i).onWillCancel = { [unowned self] navigationAction, redirect in
                XCTAssertEqual(NavAction(navigationAction), cached(0))
                XCTAssertEqual(redirect, .redirect(req(urls.local2)))
                eWillCancel.fulfill()
            }
            responder(at: i).onDidCancel = { [unowned self] navigationAction, redirect in
                XCTAssertEqual(NavAction(navigationAction), cached(0))
                XCTAssertEqual(redirect, .redirect(req(urls.local2)))
                eDidCancel.fulfill()
            }
        }

        webView.load(req(urls.local1))
        waitForExpectations(timeout: 1)
    }

    func testWhenResponderCancelsNavigationResponse_followingRespondersNotCalled() throws {
        navigationDelegate.setResponders(
            .strong(NavigationResponderMock(defaultHandler: { _ in })),
            .strong(NavigationResponderMock(defaultHandler: { _ in })),
            .strong(NavigationResponderMock(defaultHandler: { _ in }))
        )

        responder(at: 0).onNavigationResponse = { _, _ in .next }
        responder(at: 1).onNavigationResponse = { _, _ in .cancel }
        responder(at: 2).onNavigationResponse = { _, _ in XCTFail("Unexpected decidePolicyForNavigationAction:"); return .next }

        let eDidFail = expectation(description: "onDidFail")
        responder(at: 2).onDidFail = { _, _ in eDidFail.fulfill() }

        try server.start(8084)
        webView.load(req(urls.local1))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local1), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .response(Nav(action: cached(0), .resp(urls.local1, status: 404, mime: "text/plain", headers: ["Server": "Swifter Unspecified"]))),
            .didFail(Nav(action: cached(0), .failed(WKError(.frameLoadInterruptedByPolicyChange))), WKError.Code.frameLoadInterruptedByPolicyChange.rawValue)
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 2, equalsTo: [
            .navigationAction(req(urls.local1), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .didFail(Nav(action: cached(0), .failed(WKError(.frameLoadInterruptedByPolicyChange))), WKError.Code.frameLoadInterruptedByPolicyChange.rawValue)
        ])
    }

    func testWhenNavigationFails_didFailIsCalled() {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let eDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { _, _ in eDidFail.fulfill() }

        // not calling server.start
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .didFail(Nav(action: cached(0), .failed(WKError(NSURLErrorCannotConnectToHost))), NSURLErrorCannotConnectToHost)
        ])
    }

    func testWhenNavigationActionIsAllowed_followingRespondersNotCalled() throws {
        navigationDelegate.setResponders(
            .strong(NavigationResponderMock(defaultHandler: { _ in })),
            .strong(NavigationResponderMock(defaultHandler: { _ in })),
            .strong(NavigationResponderMock(defaultHandler: { _ in }))
        )

        // Regular navigation without redirects
        // 1st: .next
        let eOnNavigationAction1 = expectation(description: "onNavigationAction 1")
        responder(at: 0).onNavigationAction = { _, _ in eOnNavigationAction1.fulfill(); return .next }
        // 2nd: .allow
        let eOnNavigationAction2 = expectation(description: "onNavigationAction 2")
        responder(at: 1).onNavigationAction = { _, _ in eOnNavigationAction2.fulfill(); return .allow }
        // 3rd: not called
        responder(at: 2).onNavigationAction = { _, _ in XCTFail(); return .cancel }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 2).onDidFinish = { _ in eDidFinish.fulfill() }

        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]

        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .response(Nav(action: cached(0), .resp(urls.local, data.html.count))),
            .didCommit(Nav(action: cached(0), .resp(urls.local, data.html.count), .committed)),
            .didFinish(Nav(action: cached(0), .finished, .committed))
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 2, equalsTo: [
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .response(Nav(action: cached(0), .resp(urls.local, data.html.count))),
            .didCommit(Nav(action: cached(0), .resp(urls.local, data.html.count), .committed)),
            .didFinish(Nav(action: cached(0), .finished, .committed))
        ])
    }

    func testWhenNavigationResponseAllowed_followingRespondersNotCalled() throws {
        navigationDelegate.setResponders(
            .strong(NavigationResponderMock(defaultHandler: { _ in })),
            .strong(NavigationResponderMock(defaultHandler: { _ in })),
            .strong(NavigationResponderMock(defaultHandler: { _ in }))
        )

        responder(at: 1).onNavigationResponse = { _, _ in return .allow }
        responder(at: 2).onNavigationResponse = { _, _ in XCTFail("Unexpected decidePolicyForNavigationAction:"); return .next }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 2).onDidFinish = { _ in eDidFinish.fulfill() }

        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]

        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .response(Nav(action: cached(0), .resp(urls.local, data.html.count))),
            .didCommit(Nav(action: cached(0), .resp(urls.local, data.html.count), .committed)),
            .didFinish(Nav(action: cached(0), .finished, .committed))
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 2, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .didCommit(Nav(action: cached(0), .resp(urls.local, data.html.count), .committed)),
            .didFinish(Nav(action: cached(0), .finished, .committed))
        ])
    }

    func testWhenAuthenticationChallengeReceived_responderChainReceivesEvents() throws {
        navigationDelegate.setResponders(
            .strong(NavigationResponderMock { _ in }),
            .strong(NavigationResponderMock { _ in }),
            .strong(NavigationResponderMock { _ in })
        )

        // 1st: .next
        let eOnAuthChallenge1 = expectation(description: "OnAuthChallenge 1 1")
        responder(at: 0).onDidReceiveAuthenticationChallenge = { _, _ in
            eOnAuthChallenge1.fulfill()
            return .next
        }
        // 2nd: .credential
        let eOnAuthChallenge2 = expectation(description: "OnAuthChallenge 2")
        responder(at: 1).onDidReceiveAuthenticationChallenge = { _, _ in
            eOnAuthChallenge2.fulfill()
            return .credential(URLCredential(user: "t", password: "t", persistence: .none))
        }
        // 3rd: not called
        responder(at: 2).onDidReceiveAuthenticationChallenge = { _, _ in XCTFail(); return .cancel }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 2).onDidFinish = { _ in eDidFinish.fulfill() }

        server.middleware = [{ request in
            guard request.headers["authorization"] == nil else { return nil }
            return .raw(401, "Unauthorized", ["WWW-Authenticate": "Basic"]) { writer in
                try! writer.write("<html />".data(using: .utf8)!)
            }
        }, { request in
            return .ok(.html("<html />"))
        }]
        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .didReceiveAuthenticationChallenge(.init("localhost", 8084, "http", realm: "localhost", method: "NSURLAuthenticationMethodHTTPBasic"), Nav(action: cached(0), .started, nil, .gotAuth)),
            .response(Nav(action: cached(0), .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]), nil, .gotAuth)),
            .didCommit(Nav(action: cached(0), .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]), .committed, .gotAuth)),
            .didFinish(Nav(action: cached(0), .finished, .committed, .gotAuth))
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 2, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .response(Nav(action: cached(0), .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]), nil, .gotAuth)),
            .didCommit(Nav(action: cached(0), .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]), .committed, .gotAuth)),
            .didFinish(Nav(action: cached(0), .finished, .committed, .gotAuth))
        ])
    }

    func testWhenMultiAuthenticationChallengesReceived_responderChainReceivesEvents() throws {
        navigationDelegate.setResponders(
            .strong(NavigationResponderMock { _ in }),
            .strong(NavigationResponderMock { _ in }),
            .strong(NavigationResponderMock { _ in })
        )

        responder(at: 0).onDidReceiveAuthenticationChallenge = { _, _ in .next }
        responder(at: 1).onDidReceiveAuthenticationChallenge = { challenge, _ in
            return .credential(URLCredential(user: "t", password: "t", persistence: .none))
        }
        responder(at: 2).onDidReceiveAuthenticationChallenge = { _, _ in .next }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 2).onDidFinish = { _ in eDidFinish.fulfill() }

        server.middleware = [{ [data=self.data] request in
            guard request.path == "/3" else { return nil }
            guard request.headers["authorization"] == nil else { return .ok(.data(data.html)) }
            return .raw(401, "Unauthorized", ["WWW-Authenticate": "Basic"]) { writer in
                try! writer.write(data.html)
            }
        }, { [data=self.data] request in
            guard request.headers["authorization"] == nil else { return nil }
            return .raw(401, "Unauthorized", ["WWW-Authenticate": "Basic"]) { writer in
                try! writer.write(data.html)
            }
        }, { [data=self.data] request in
            return .ok(.data(data.htmlWithIframe3))
        }]
        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .didReceiveAuthenticationChallenge(.init("localhost", 8084, "http", realm: "localhost", method: "NSURLAuthenticationMethodHTTPBasic"), Nav(action: cached(0), .started, nil, .gotAuth)),
            .response(Nav(action: cached(0), .resp(urls.local, data.htmlWithIframe3.count), nil, .gotAuth)),
            .didCommit(Nav(action: cached(0), .resp(urls.local, data.htmlWithIframe3.count), .committed, .gotAuth)),
            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": "http://localhost:8084/"]), .other, from: webView.item(at: 0), src: frame(4, urls.local), targ: frame(9, .empty, secOrigin: urls.local.securityOrigin)),
            .didReceiveAuthenticationChallenge(.init("localhost", 8084, "http", realm: "localhost", method: "NSURLAuthenticationMethodHTTPBasic"), Nav(action: cached(0), .resp(urls.local, data.htmlWithIframe3.count), .committed, .gotAuth)),
            .response(.resp(resp(urls.local3, data.html.count), .nonMain), Nav(action: cached(0), .resp(urls.local, data.htmlWithIframe3.count), .committed, .gotAuth)),
            .didFinish(Nav(action: cached(0), .finished, .committed, .gotAuth))
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 2, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .response(Nav(action: cached(0), .resp(urls.local, data.htmlWithIframe3.count), nil, .gotAuth)),
            .didCommit(Nav(action: cached(0), .resp(urls.local, data.htmlWithIframe3.count), .committed, .gotAuth)),
            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": "http://localhost:8084/"]), .other, from: webView.item(at: 0), src: frame(4, urls.local), targ: frame(9, .empty, secOrigin: urls.local.securityOrigin)),
            .response(.resp(resp(urls.local3, data.html.count), .nonMain), Nav(action: cached(0), .resp(urls.local, data.htmlWithIframe3.count), .committed, .gotAuth)),
            .didFinish(Nav(action: cached(0), .finished, .committed, .gotAuth))
        ])
    }

    func testWhenAuthenticationChallengeReturnsNext_responderChainReceivesEvents() throws {
        navigationDelegate.setResponders(
            .strong(NavigationResponderMock { _ in }),
            .strong(NavigationResponderMock { _ in }),
            .strong(NavigationResponderMock { _ in })
        )

        let eOnAuthChallenge3 = expectation(description: "OnAuthChallenge 1 1")
        responder(at: 0).onDidReceiveAuthenticationChallenge = { _, _ in .next }
        responder(at: 1).onDidReceiveAuthenticationChallenge = { _, _ in .next }
        responder(at: 2).onDidReceiveAuthenticationChallenge = { _, _ in
            eOnAuthChallenge3.fulfill()
            return .next
        }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 2).onDidFinish = { _ in eDidFinish.fulfill() }

        server.middleware = [{ request in
            guard request.headers["authorization"] == nil else { return nil }
            return .raw(401, "Unauthorized", ["WWW-Authenticate": "Basic"]) { writer in
                try! writer.write("<html />".data(using: .utf8)!)
            }
        }]
        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .didReceiveAuthenticationChallenge(.init("localhost", 8084, "http", realm: "localhost", method: "NSURLAuthenticationMethodHTTPBasic"), Nav(action: cached(0), .started, nil, .gotAuth)),
            .response(Nav(action: cached(0), .resp(urls.local, status: 401, headers: ["Www-Authenticate": "Basic", "Server": "Swifter Unspecified"]), nil, .gotAuth)),
            .didCommit(Nav(action: cached(0), .resp(urls.local, status: 401, headers: ["Www-Authenticate": "Basic", "Server": "Swifter Unspecified"]), .committed, .gotAuth)),
            .didFinish(Nav(action: cached(0), .finished, .committed, .gotAuth))
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 1, equalsToHistoryOfResponderAt: 2)
    }

    func testWhenAuthenticationChallengeReturnsCancel_responderChainReceivesFailure() throws {
        navigationDelegate.setResponders(
            .strong(NavigationResponderMock { _ in }),
            .strong(NavigationResponderMock { _ in }),
            .strong(NavigationResponderMock { _ in })
        )

        responder(at: 0).onDidReceiveAuthenticationChallenge = { _, _ in .next }
        responder(at: 1).onDidReceiveAuthenticationChallenge = { _, _ in .cancel }
        responder(at: 2).onDidReceiveAuthenticationChallenge = { _, _ in XCTFail("Unexpected onDidReceiveAuthenticationChallenge"); return .next }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 2).onDidFail = { _, _ in eDidFinish.fulfill() }

        server.middleware = [{ request in
            guard request.headers["authorization"] == nil else { return nil }
            return .raw(401, "Unauthorized", ["WWW-Authenticate": "Basic"]) { writer in
                try! writer.write("<html />".data(using: .utf8)!)
            }
        }]
        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .didReceiveAuthenticationChallenge(.init("localhost", 8084, "http", realm: "localhost", method: "NSURLAuthenticationMethodHTTPBasic"), Nav(action: cached(0), .started, nil, .gotAuth)),
            .didFail(Nav(action: cached(0), .failed(WKError(NSURLErrorCancelled)), nil, .gotAuth), NSURLErrorCancelled)
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 2, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .didFail(Nav(action: cached(0), .failed(WKError(NSURLErrorCancelled)), nil, .gotAuth), NSURLErrorCancelled)
        ])
    }

    func testWhenAuthenticationChallengeRejected_responderChainReceivesEvents() throws {
        navigationDelegate.setResponders(
            .strong(NavigationResponderMock { _ in }),
            .strong(NavigationResponderMock { _ in }),
            .strong(NavigationResponderMock { _ in })
        )

        responder(at: 0).onDidReceiveAuthenticationChallenge = { _, _ in .next }
        responder(at: 1).onDidReceiveAuthenticationChallenge = { _, _ in .rejectProtectionSpace }
        responder(at: 2).onDidReceiveAuthenticationChallenge = { _, _ in XCTFail("Unexpected onDidReceiveAuthenticationChallenge"); return .next }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 2).onDidFinish = { _ in eDidFinish.fulfill() }

        server.middleware = [{ request in
            guard request.headers["authorization"] == nil else { return nil }
            return .raw(401, "Unauthorized", ["WWW-Authenticate": "Basic"]) { writer in
                try! writer.write("<html />".data(using: .utf8)!)
            }
        }]
        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .didReceiveAuthenticationChallenge(.init("localhost", 8084, "http", realm: "localhost", method: "NSURLAuthenticationMethodHTTPBasic"), Nav(action: cached(0), .started, nil, .gotAuth)),
            .response(Nav(action: cached(0), .resp(urls.local, status: 401, headers: ["Server": "Swifter Unspecified", "Www-Authenticate": "Basic"]), nil, .gotAuth)),
            .didCommit(Nav(action: cached(0), .resp(urls.local, status: 401, headers: ["Server": "Swifter Unspecified", "Www-Authenticate": "Basic"]), .committed, .gotAuth)),
            .didFinish(Nav(action: cached(0), .finished, .committed, .gotAuth))
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 2, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .response(Nav(action: cached(0), .resp(urls.local, status: 401, headers: ["Server": "Swifter Unspecified", "Www-Authenticate": "Basic"]), nil, .gotAuth)),
            .didCommit(Nav(action: cached(0), .resp(urls.local, status: 401, headers: ["Server": "Swifter Unspecified", "Www-Authenticate": "Basic"]), .committed, .gotAuth)),
            .didFinish(Nav(action: cached(0), .finished, .committed, .gotAuth))
        ])
    }

    func testWhenSessionIsRestored_navigationTypeIsSessionRestoration() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        try server.start(8084)
        webView.interactionState = data.interactionStateData
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local, cachePolicy: .returnCacheDataElseLoad), .restore, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .response(Nav(action: cached(0), .resp(urls.local, status: 404, mime: "text/plain", headers: ["Server": "Swifter Unspecified"]))),
            .didCommit(Nav(action: cached(0), .resp(urls.local, status: 404, mime: "text/plain", headers: ["Server": "Swifter Unspecified"]), .committed)),
            .didFinish(Nav(action: cached(0), .finished, .committed))
        ])
    }

    func testGoBackAfterSessionRestoration() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        server.middleware = [{ request in
            return .ok(.html("<html />"))
        }]
        try server.start(8084)

        webView.interactionState = data.interactionStateData
        waitForExpectations(timeout: 1)

        let eDidFinish2 = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish2.fulfill() }
        responder(at: 0).clear()
        webView.goBack()
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local1, cachePolicy: .returnCacheDataElseLoad), .backForw(-1), from: webView.item(at: 1), src: main(urls.local)),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .response(Nav(action: cached(0), .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: cached(0), .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: cached(0), .finished, .committed))
        ])
    }

    func testGoBackAfterSessionRestorationCacheFailure() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let eDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { _, _ in eDidFail.fulfill() }

        // restore before server startup to raise cache failure
        webView.interactionState = data.interactionStateData
        waitForExpectations(timeout: 1)

        server.middleware = [{ request in
            return .ok(.html("<html />"))
        }]
        try server.start(8084)

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        webView.goBack()
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local, cachePolicy: .returnCacheDataElseLoad), .restore, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .didFail(Nav(action: cached(0), .failed(WKError(NSURLErrorCannotConnectToHost))), NSURLErrorCannotConnectToHost),

            .navigationAction(req(urls.local1, cachePolicy: .returnCacheDataElseLoad), .backForw(-1), from: webView.item(at: 1), src: main()),
            .willStart(cached(1)),
            .didStart(Nav(action: cached(1), .started)),
            .response(Nav(action: cached(1), .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: cached(1), .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: cached(1), .finished, .committed))
        ])
    }

    // TODO: Is Go Back raising didCommit and updating currentHistoryItemIdentity correctly?
    // TODO: Go Back in non-main frame
    // TODO: Go Back in non-main frame after failing session restoration

    func testWhenAboutPrefsSessionIsRestored_navigationTypeIsSessionRestoration() {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        webView.interactionState = data.aboutPrefsAfterRegularNavigationInteractionStateData
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .willStart(.init(req(urls.aboutBlank, [:], cachePolicy: .returnCacheDataElseLoad), .restore, src: main())),
            .didStart(Nav(action: cached(0), .started)),
            .didCommit(Nav(action: cached(0), .started, .committed)),
            .didFinish(Nav(action: cached(0), .finished, .committed))
        ])
    }

    // initial about: navigation doesn‘t wait for decidePolicyForNavigationAction
    func testAboutNavigation() {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        webView.load(req(urls.aboutPrefs))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .willStart(.init(req(urls.aboutPrefs), .other, src: main())),
            .didStart(Nav(action: cached(0), .started)),
            .didCommit(Nav(action: cached(0), .started, .committed)),
            .didFinish(Nav(action: cached(0), .finished, .committed))
        ])
    }

    func testAboutNavigationAfterRegularNavigation() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let eDidFinish = expectation(description: "onDidFinish 1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        server.middleware = [{ request in
            return .ok(.data(self.data.html))
        }]

        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        let eDidFinish2 = expectation(description: "onDidFinish 2")
        responder(at: 0).onDidFinish = { _ in eDidFinish2.fulfill() }
        webView.load(req(urls.aboutBlank))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .response(Nav(action: cached(0), .resp(urls.local, data.html.count))),
            .didCommit(Nav(action: cached(0), .resp(urls.local, data.html.count), .committed)),
            .didFinish(Nav(action: cached(0), .finished, .committed)),

            .navigationAction(req(urls.aboutBlank), .other, from: webView.item(at: -1), src: main(urls.local)),
            .willStart(cached(1)),
            .didStart(Nav(action: cached(1), .started)),
            .didCommit(Nav(action: cached(1), .started, .committed)),
            .didFinish(Nav(action: cached(1), .finished, .committed))
        ])
    }

    func testServerRedirect() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        server.middleware = [{ [urls, data] request in
            switch request.path {
            case urls.local2.path:
                return .raw(301, "Moved", ["Location": urls.local3.path]) { writer in
                    try! writer.write(data.empty)
                }
            case urls.local3.path:
                return .ok(.data(data.html))
            default:
                return .raw(301, "Moved", ["Location": urls.local2.path]) { writer in
                    try! writer.write(data.empty)
                }
            }
        }]
        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),

            .navigationAction(req(urls.local2, defaultHeaders + ["Upgrade-Insecure-Requests": "1", "Accept-Encoding": "gzip, deflate", "Accept-Language": "en-GB,en;q=0.9"]), .redirect(.server), redirects: [cached(0)], src: main()),
            .willStart(cached(1)),
            .didReceiveRedirect(Nav(action: cached(1), redirects: [cached(0)], .started)),

            .navigationAction(req(urls.local3, defaultHeaders + ["Accept-Encoding": "gzip, deflate", "Accept-Language": "en-GB,en;q=0.9", "Upgrade-Insecure-Requests": "1"]), .redirect(.server), redirects: [cached(0), cached(1)], src: main()),
            .willStart(cached(2)),
            .didReceiveRedirect(Nav(action: cached(2), redirects: [cached(0), cached(1)], .started)),

            .response(Nav(action: cached(2), redirects: [cached(0), cached(1)], .resp(urls.local3, data.html.count))),
            .didCommit(Nav(action: cached(2), redirects: [cached(0), cached(1)], .resp(urls.local3, data.html.count), .committed)),
            .didFinish(Nav(action: cached(2), redirects: [cached(0), cached(1)], .finished, .committed))
        ])
    }

    func testMetaRedirectAfterServerRedirect() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish1 = expectation(description: "onDidFinish 1")
        let eDidFinish2 = expectation(description: "onDidFinish 2")
        var eDidFinish = eDidFinish1
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
            eDidFinish = eDidFinish2
        }

        server.middleware = [{ [urls, data] request in
            print(request.path)
            switch request.path {
            case urls.local2.path:
                return .ok(.data(data.metaRedirect))
            case urls.local3.path:
                return .raw(301, "Moved", ["Location": urls.local4.path]) { writer in
                    try! writer.write(data.empty)
                }
            case urls.local4.path:
                return .ok(.data(data.html))
            default:
                return .raw(301, "Moved", ["Location": urls.local2.path]) { writer in
                    try! writer.write(data.empty)
                }
            }
        }]
        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),

            .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Language": "en-GB,en;q=0.9", "Upgrade-Insecure-Requests": "1", "Accept-Encoding": "gzip, deflate"]), .redirect(.server), redirects: [cached(0)], src: main()),
            .willStart(cached(1)),
            .didReceiveRedirect(Nav(action: cached(1), redirects: [cached(0)], .started)),

            .response(Nav(action: cached(1), redirects: [cached(0)], .resp(urls.local2, data.metaRedirect.count))),
            .didCommit(Nav(action: cached(1), redirects: [cached(0)], .resp(urls.local2, data.metaRedirect.count), .committed)),
            .didFinish(Nav(action: cached(1), redirects: [cached(0)], .finished, .committed)),

            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": "http://localhost:8084/2"]), .redirect(.client), from: webView.item(at: 0), redirects: [cached(0), cached(1)], src: main(urls.local2)),
            .willStart(cached(2)),
            .didStart(Nav(action: cached(2), redirects: [cached(0), cached(1)], .started)),

            .navigationAction(req(urls.local4, defaultHeaders + ["Accept-Encoding": "gzip, deflate", "Upgrade-Insecure-Requests": "1", "Accept-Language": "en-GB,en;q=0.9", "Referer": "http://localhost:8084/2"]), .redirect(.server), from: webView.item(at: 0), redirects: [cached(0), cached(1), cached(2)], src: main(urls.local2)),
            .willStart(cached(3)),
            .didReceiveRedirect(Nav(action: cached(3), redirects: [cached(0), cached(1), cached(2)], .started)),

            .response(Nav(action: cached(3), redirects: [cached(0), cached(1), cached(2)], .resp(urls.local4, data.html.count))),
            .didCommit(Nav(action: cached(3), redirects: [cached(0), cached(1), cached(2)], .resp(urls.local4, data.html.count), .committed)),
            .didFinish(Nav(action: cached(3), redirects: [cached(0), cached(1), cached(2)], .finished, .committed))
        ])
    }

    func testMetaRedirectAfterServerRedirectWithDidFinishReceivedBeforeWillStartNavigationAction() throws {
        navigationDelegateProxy.finishEventsDispatchTime = .beforeWillStartNavigationAction
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish1 = expectation(description: "onDidFinish 1")
        let eDidFinish2 = expectation(description: "onDidFinish 2")
        var eDidFinish = eDidFinish1
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
            eDidFinish = eDidFinish2
        }

        server.middleware = [{ [urls, data] request in
            print(request.path)
            switch request.path {
            case urls.local2.path:
                return .ok(.data(data.metaRedirect))
            case urls.local3.path:
                return .raw(301, "Moved", ["Location": urls.local4.path]) { writer in
                    try! writer.write(data.empty)
                }
            case urls.local4.path:
                return .ok(.data(data.html))
            default:
                return .raw(301, "Moved", ["Location": urls.local2.path]) { writer in
                    try! writer.write(data.empty)
                }
            }
        }]
        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),

            .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Language": "en-GB,en;q=0.9", "Upgrade-Insecure-Requests": "1", "Accept-Encoding": "gzip, deflate"]), .redirect(.server), redirects: [cached(0)], src: main()),
            .willStart(cached(1)),
            .didReceiveRedirect(Nav(action: cached(1), redirects: [cached(0)], .started)),

            .response(Nav(action: cached(1), redirects: [cached(0)], .resp(urls.local2, data.metaRedirect.count))),
            .didCommit(Nav(action: cached(1), redirects: [cached(0)], .resp(urls.local2, data.metaRedirect.count), .committed)),

            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": "http://localhost:8084/2"]), .redirect(.client), from: webView.item(at: 0), redirects: [cached(0), cached(1)], src: main(urls.local2)),
            .didFinish(Nav(action: cached(1), redirects: [cached(0)], .finished, .committed)),

            .willStart(cached(2)),
            .didStart(Nav(action: cached(2), redirects: [cached(0), cached(1)], .started)),

            .navigationAction(req(urls.local4, defaultHeaders + ["Accept-Encoding": "gzip, deflate", "Upgrade-Insecure-Requests": "1", "Accept-Language": "en-GB,en;q=0.9", "Referer": "http://localhost:8084/2"]), .redirect(.server), from: webView.item(at: 0), redirects: [cached(0), cached(1), cached(2)], src: main(urls.local2)),
            .willStart(cached(3)),
            .didReceiveRedirect(Nav(action: cached(3), redirects: [cached(0), cached(1), cached(2)], .started)),

            .response(Nav(action: cached(3), redirects: [cached(0), cached(1), cached(2)], .resp(urls.local4, data.html.count))),
            .didCommit(Nav(action: cached(3), redirects: [cached(0), cached(1), cached(2)], .resp(urls.local4, data.html.count), .committed)),
            .didFinish(Nav(action: cached(3), redirects: [cached(0), cached(1), cached(2)], .finished, .committed))
        ])
    }

    func testMetaRedirectAfterServerRedirectWithDidFinishReceivedAfterWillStartNavigationAction() throws {
        navigationDelegateProxy.finishEventsDispatchTime = .afterWillStartNavigationAction
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish1 = expectation(description: "onDidFinish 1")
        let eDidFinish2 = expectation(description: "onDidFinish 2")
        var eDidFinish = eDidFinish1
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
            eDidFinish = eDidFinish2
        }

        server.middleware = [{ [urls, data] request in
            print(request.path)
            switch request.path {
            case urls.local2.path:
                return .ok(.data(data.metaRedirect))
            case urls.local3.path:
                return .raw(301, "Moved", ["Location": urls.local4.path]) { writer in
                    try! writer.write(data.empty)
                }
            case urls.local4.path:
                return .ok(.data(data.html))
            default:
                return .raw(301, "Moved", ["Location": urls.local2.path]) { writer in
                    try! writer.write(data.empty)
                }
            }
        }]
        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),

            .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Language": "en-GB,en;q=0.9", "Upgrade-Insecure-Requests": "1", "Accept-Encoding": "gzip, deflate"]), .redirect(.server), redirects: [cached(0)], src: main()),
            .willStart(cached(1)),
            .didReceiveRedirect(Nav(action: cached(1), redirects: [cached(0)], .started)),

            .response(Nav(action: cached(1), redirects: [cached(0)], .resp(urls.local2, data.metaRedirect.count))),
            .didCommit(Nav(action: cached(1), redirects: [cached(0)], .resp(urls.local2, data.metaRedirect.count), .committed)),

            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": "http://localhost:8084/2"]), .redirect(.client), from: webView.item(at: 0), redirects: [cached(0), cached(1)], src: main(urls.local2)),
            .willStart(cached(2)),
            .didFinish(Nav(action: cached(1), redirects: [cached(0)], .finished, .committed)),

            .didStart(Nav(action: cached(2), redirects: [cached(0), cached(1)], .started)),

            .navigationAction(req(urls.local4, defaultHeaders + ["Accept-Encoding": "gzip, deflate", "Upgrade-Insecure-Requests": "1", "Accept-Language": "en-GB,en;q=0.9", "Referer": "http://localhost:8084/2"]), .redirect(.server), from: webView.item(at: 0), redirects: [cached(0), cached(1), cached(2)], src: main(urls.local2)),
            .willStart(cached(3)),
            .didReceiveRedirect(Nav(action: cached(3), redirects: [cached(0), cached(1), cached(2)], .started)),

            .response(Nav(action: cached(3), redirects: [cached(0), cached(1), cached(2)], .resp(urls.local4, data.html.count))),
            .didCommit(Nav(action: cached(3), redirects: [cached(0), cached(1), cached(2)], .resp(urls.local4, data.html.count), .committed)),
            .didFinish(Nav(action: cached(3), redirects: [cached(0), cached(1), cached(2)], .finished, .committed))
        ])
    }

    func testMetaRedirectAfterServerRedirectWithDidFinishReceivedAfterDidStartNavigationAction() throws {
        navigationDelegateProxy.finishEventsDispatchTime = .afterDidStartNavigationAction
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish1 = expectation(description: "onDidFinish 1")
        let eDidFinish2 = expectation(description: "onDidFinish 2")
        var eDidFinish = eDidFinish1
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
            eDidFinish = eDidFinish2
        }

        server.middleware = [{ [urls, data] request in
            print(request.path)
            switch request.path {
            case urls.local2.path:
                return .ok(.data(data.metaRedirect))
            case urls.local3.path:
                return .raw(301, "Moved", ["Location": urls.local4.path]) { writer in
                    try! writer.write(data.empty)
                }
            case urls.local4.path:
                return .ok(.data(data.html))
            default:
                return .raw(301, "Moved", ["Location": urls.local2.path]) { writer in
                    try! writer.write(data.empty)
                }
            }
        }]
        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),

            .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Language": "en-GB,en;q=0.9", "Upgrade-Insecure-Requests": "1", "Accept-Encoding": "gzip, deflate"]), .redirect(.server), redirects: [cached(0)], src: main()),
            .willStart(cached(1)),
            .didReceiveRedirect(Nav(action: cached(1), redirects: [cached(0)], .started)),

            .response(Nav(action: cached(1), redirects: [cached(0)], .resp(urls.local2, data.metaRedirect.count))),
            .didCommit(Nav(action: cached(1), redirects: [cached(0)], .resp(urls.local2, data.metaRedirect.count), .committed)),

            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": "http://localhost:8084/2"]), .redirect(.client), from: webView.item(at: 0), redirects: [cached(0), cached(1)], src: main(urls.local2)),
            .willStart(cached(2)),
            .didStart(Nav(action: cached(2), redirects: [cached(0), cached(1)], .started)),
            .didFinish(Nav(action: cached(1), redirects: [cached(0)], .finished, .committed)),

            .navigationAction(req(urls.local4, defaultHeaders + ["Accept-Encoding": "gzip, deflate", "Upgrade-Insecure-Requests": "1", "Accept-Language": "en-GB,en;q=0.9", "Referer": "http://localhost:8084/2"]), .redirect(.server), from: webView.item(at: 0), redirects: [cached(0), cached(1), cached(2)], src: main(urls.local2)),
            .willStart(cached(3)),
            .didReceiveRedirect(Nav(action: cached(3), redirects: [cached(0), cached(1), cached(2)], .started)),

            .response(Nav(action: cached(3), redirects: [cached(0), cached(1), cached(2)], .resp(urls.local4, data.html.count))),
            .didCommit(Nav(action: cached(3), redirects: [cached(0), cached(1), cached(2)], .resp(urls.local4, data.html.count), .committed)),
            .didFinish(Nav(action: cached(3), redirects: [cached(0), cached(1), cached(2)], .finished, .committed))
        ])
    }

    func testSameURLServerRedirects() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish = expectation(description: "eDidFinish")
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
        }

        var counter = 0
        server.middleware = [{ [urls, data] request in
            guard counter < 10 else {
                return .ok(.data(data.html))
            }
            counter += 1
            return .raw(301, "Moved", ["Location": urls.local2.path]) { writer in
                try! writer.write(data.empty)
            }
        }]
        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 100)

        var expected: [NavigationEvent] =  [

            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Language": "en-GB,en;q=0.9", "Upgrade-Insecure-Requests": "1", "Accept-Encoding": "gzip, deflate"]), .redirect(.server), redirects: [cached(0)], src: main()),
            .willStart(cached(1)),
            .didReceiveRedirect(Nav(action: cached(1), redirects: [cached(0)], .started)),
            // .didReceiveRedirect(Nav(action: cached(1), redirects: [cached(0), cached(1)...], .started)),

            .response(Nav(action: cached(1), redirects: [cached(0)] + .init(repeating: cached(1), count: 9), .resp(urls.local2, data.html.count))),
            .didCommit(Nav(action: cached(1), redirects: [cached(0)] + .init(repeating: cached(1), count: 9), .resp(urls.local2, data.html.count), .committed)),
            .didFinish(Nav(action: cached(1), redirects: [cached(0)] + .init(repeating: cached(1), count: 9), .finished, .committed))
        ]
        while expected[expected.count - 4].redirectEvent!.redirects.count < 10 {
            expected.insert(.didReceiveRedirect(Nav(action: cached(1),
                                                    redirects: [cached(0)]
                                                    + .init(repeating: cached(1), count: expected[expected.count - 4].redirectEvent!.redirects.count),
                                                    .started)), at: expected.count - 3)
        }

        assertHistory(ofResponderAt: 0, equalsTo: expected)
    }

    func testSameURLServerRedirectsFailing() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { _, _ in
            eDidFail.fulfill()
        }

        var counter = 0
        server.middleware = [{ [urls, data] request in
            guard counter < 100 else {
                return .ok(.data(data.html))
            }
            counter += 1
            return .raw(301, "Moved", ["Location": urls.local2.path]) { writer in
                try! writer.write(data.empty)
            }
        }]
        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 100)

        var expected: [NavigationEvent] =  [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),

            .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Language": "en-GB,en;q=0.9", "Upgrade-Insecure-Requests": "1", "Accept-Encoding": "gzip, deflate"]), .redirect(.server), redirects: [cached(0)], src: main()),
            .willStart(cached(1)),
            .didReceiveRedirect(Nav(action: cached(1), redirects: [cached(0)], .started)),
            // ...didReceiveRedirect(Nav(action: cached(1), redirects: [cached(0), cached(1)...], .started)

            .didFail(Nav(action: cached(1), redirects: [cached(0)] + .init(repeating: cached(1), count: 19), .failed(WKError(NSURLErrorHTTPTooManyRedirects))), NSURLErrorHTTPTooManyRedirects)
        ]
        while expected[expected.count - 2].redirectEvent!.redirects.count < 20 {
            expected.insert(.didReceiveRedirect(Nav(action: cached(1),
                                                    redirects: [cached(0)]
                                                        + .init(repeating: cached(1), count: expected[expected.count - 2].redirectEvent!.redirects.count),
                                                    .started)), at: expected.count - 1)
        }

        assertHistory(ofResponderAt: 0, equalsTo: expected)
    }

    func testCustomSchemeHandlerRequest() {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        testSchemeHandler.onRequest = { [responseData=data.html] task in
            task.didReceive(.response(for: task.request, mimeType: "text/html", expectedLength: responseData.count))
            task.didReceive(responseData)
            task.didFinish()
        }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        webView.load(req(urls.testScheme))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.testScheme), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .response(Nav(action: cached(0), .resp(urls.testScheme, status: nil, data.html.count))),
            .didCommit(Nav(action: cached(0), .resp(urls.testScheme, status: nil, data.html.count), .committed)),
            .didFinish(Nav(action: cached(0), .finished, .committed))
        ])
    }
//
//    func testCustomSchemeHandlerReturningRequestWithAnotherURL() {
////        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
////        testSchemeHandler.onRequest = { [responseData=data.html] task in
////            task.didReceive(.response(for: task.request, mimeType: "text/html", expectedLength: responseData.count))
////            task.didReceive(responseData)
////            task.didFinish()
////        }
////        let eDidFinish = expectation(description: "onDidFinish")
////        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
////        webView.load(req(urls.testScheme))
////
////        waitForExpectations(timeout: 1)
////
////        assertHistoryEquals(responder(at: 0).history, [
////            .navigationAction(req(urls.testScheme), .other, src: main()),
////            .willStart(0),
////            .didStart(Nav(action: 0, .started)),
////            .response(Nav(action: 0, .resp(urls.testScheme, status: nil, data.html.count))),
////            .didCommit(Nav(action: 0, .resp(urls.testScheme, status: nil, data.html.count), .committed)),
////            .didFinish(Nav(action: 0, .finished, .committed))
////        ])
//    }

    func testSimulatedRequest() {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        webView.loadSimulatedRequest(req(urls.https), responseHTML: String(data: data.html, encoding: .utf8)!)
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.https), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .didCommit(Nav(action: cached(0), .started, .committed)),
            .didFinish(Nav(action: cached(0), .finished, .committed))
        ])
    }

    func testSimulatedRequestAfterCustomSchemeRequest() {
        // receive didFailProvisionalNavigation AFTER decidePolicyForNavigationAction for loadSimulatedRequest (because it works different in runtime than in tests)
        navigationDelegateProxy.finishEventsDispatchTime = .afterWillStartNavigationAction
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        testSchemeHandler.onRequest = { [webView, data, urls] task in
            webView.loadSimulatedRequest(req(urls.https), responseHTML: String(data: data.html, encoding: .utf8)!)
        }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        webView.load(req(urls.testScheme))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.testScheme), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),

            .navigationAction(req(urls.https), .other, src: main()),
            .willStart(cached(1)),
            .didFail(Nav(action: cached(0), .failed(WKError(-999))), -999),
            .didStart(Nav(action: cached(1), .started)),
            .didCommit(Nav(action: cached(1), .started, .committed)),
            .didFinish(Nav(action: cached(1), .finished, .committed))
        ])
    }

    func testSimulatedRequestAfterCustomSchemeRequestWithFailureBeforeWillStartNavigation() {
        // receive didFailProvisionalNavigation AFTER decidePolicyForNavigationAction for loadSimulatedRequest (works different in runtime than in tests)
        navigationDelegateProxy.finishEventsDispatchTime = .beforeWillStartNavigationAction
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        testSchemeHandler.onRequest = { [webView, data, urls] task in
            webView.loadSimulatedRequest(req(urls.https), responseHTML: String(data: data.html, encoding: .utf8)!)
        }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        webView.load(req(urls.testScheme))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.testScheme), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),

            .navigationAction(req(urls.https), .other, src: main()),
            .didFail(Nav(action: cached(0), .failed(WKError(NSURLErrorCancelled))), NSURLErrorCancelled),

            .willStart(cached(1)),
            .didStart(Nav(action: cached(1), .started)),
            .didCommit(Nav(action: cached(1), .started, .committed)),
            .didFinish(Nav(action: cached(1), .finished, .committed))
        ])
    }

    func testSimulatedRequestAfterCustomSchemeRequestWithFailureAfterDidStartNavigation() {
        // receive didFailProvisionalNavigation AFTER decidePolicyForNavigationAction for loadSimulatedRequest (works different in runtime than in tests)
        navigationDelegateProxy.finishEventsDispatchTime = .afterDidStartNavigationAction
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        testSchemeHandler.onRequest = { [webView, data, urls] task in
            webView.loadSimulatedRequest(req(urls.https), responseHTML: String(data: data.html, encoding: .utf8)!)
        }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        webView.load(req(urls.testScheme))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.testScheme), .other, src: main()),
            .willStart(cached(0)),
            .didStart(Nav(action: cached(0), .started)),
            .navigationAction(req(urls.https), .other, src: main()),
            .willStart(cached(1)),
            .didStart(Nav(action: cached(1), .started)),
            .didFail(Nav(action: cached(0), .failed(WKError(NSURLErrorCancelled))), NSURLErrorCancelled),
            .didCommit(Nav(action: cached(1), .started, .committed)),
            .didFinish(Nav(action: cached(1), .finished, .committed))
        ])
    }

//    func testRealRequestAfterCustomSchemeRequest() {
//        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
//        testSchemeHandler.onRequest = { [responseData=data.html] task in
//            // TODO: real request
//        }
//        let eDidFinish = expectation(description: "onDidFinish")
//        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
//        webView.load(req(urls.testScheme))
//
//        waitForExpectations(timeout: 1)
//
//        assertHistoryEquals(responder(at: 0).history, [
//            .navigationAction(req(urls.testScheme), .other, src: main()),
//            .willStart(0),
//            .didStart(Nav(action: 0, .started)),
//            .response(Nav(action: 0, .resp(urls.testScheme, status: nil, data.html.count))),
//            .didCommit(Nav(action: 0, .resp(urls.testScheme, status: nil, data.html.count), .committed)),
//            .didFinish(Nav(action: 0, .finished, .committed))
//        ])
//
//    }
//
//    func testStopLoading() {
//
//    }
//    func testNewUserInitiatedRequestWhileCustomSchemeRequestInProgress() {
//
//    }
//
//    // TODO: Test duck player custom scheme+server redirect
//    // TODO: Test simulated request after normal request
//    // TODO: Test custom scheme session restoration
//    // TODO: Test about:blank restoration
//
//    // TODO: Test loading interruption by new request
//
//    // TODO: Test regular back navigation
//    // TODO: Test regular forward navigation
//
////    func testGoBackInterruptingLoadAsync() {
////        performAndWaitForDidFinish {
////            self.webView.load(self.testSchemeRequest)
////        }
////        performAndWaitForDidFinish {
////            self.
////        }
////        navigationDelegate.setResponders(.strong(NavigationResponderMock()))
//////
//////        responder(at: 0).onNavigationAction = { _, _ in .allow }
////        testSchemeHandler.onRequest = { [responseData] task in
////            task.didReceive(.response(for: task.request))
////            task.didReceive(responseData)
//////
//////            DispatchQueue.main.async {
////            print(self.webView.backForwardList.backList)
////                self.webView.goBack()
////                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
////                    task.didFinish()
////                }
////
//////            }
////
////        }
////        let eDidFinish = expectation(description: "onDidFinish")
////        responder(at: 0).onDidFinish = { navigation in
////            if navigation.url == Self.testSchemeURL {
////                eDidFinish.fulfill()
////            }
////
////        }
////////        block()
////////        waitForExpectations(timeout: 1)
////        DispatchQueue.main.async {
////            self.webView.load(self.redirectSchemeRequest)
////        }
////
////        waitForExpectations(timeout: 10)
////        print(responder(at: 0).history.map { $0.description }.joined(separator: "\n"))
////    }
////
////    func testGoBackInterruptingLoad() {
////        performAndWaitForDidFinish { self.webView.load(self.testSchemeRequest) }
////
////        navigationDelegate.setResponders(.strong(NavigationResponderMock()))
////        let eDidFinish = expectation(description: "onDidFinish")
////        responder(at: 0).onDidFinish = { _ in
////            eDidFinish.fulfill()
////        }
////
////        testSchemeHandler.onRequest = { [unowned self, responseData] task in
////            print("did receive request 2")
////            task.didReceive(.response(for: task.request))
////            task.didReceive(responseData)
////            print("go back!")
////
////            self.webView.goBack()
////        }
////
////        let expectedNavAction = NavigationAction(navigationType: .unknown, request: self.testSchemeRequest, sourceFrame: .mainFrame(for: webView), targetFrame: .mainFrame(for: webView), shouldDownload: false)
////        let navIdentity = NavigationIdentity.autoresolvedOnFirstCompare
////        let expectedResponse = NavigationResponse(response: .response(for: testSchemeRequest), isForMainFrame: true, canShowMIMEType: true)
////        let expectedEvents: [NavigationEvent] = [
////            .navigationAction(expectedNavAction),
////            .willStart(expectedNavAction),
////            .didStart(.init(navigationAction: expectedNavAction, state: .started, identity: navIdentity)),
////            .navigationResponse(expectedResponse, .init(navigationAction: expectedNavAction, state: .responseReceived(expectedResponse), identity: navIdentity)),
////            .didCommit(.init(navigationAction: expectedNavAction, state: .responseReceived(expectedResponse), identity: navIdentity, isCommitted: true)),
////            .willFinish(.init(navigationAction: expectedNavAction, state: .awaitingFinishOrClientRedirect, identity: navIdentity, isCommitted: true)),
////            .didFinish(.init(navigationAction: expectedNavAction, state: .finished, identity: navIdentity, isCommitted: true)),
////        ]
////        DispatchQueue.main.async {
////            self.webView.load(self.redirectSchemeRequest)
////        }
////        waitForExpectations(timeout: 10)
////        print(responder(at: 0).history.map { $0.description }.joined(separator: "\n"))
////        assertHistoryEquals(responder(at: 0).history, expectedEvents)
////    }
////
////    func testBackNavigationInterruptingLoad() {
//////        navigationDelegate.setResponders(.strong(NavigationResponderMock()))
////
//////        testSchemeHandler.onRequest = { [responseData] task in
//////            print("did receive request")
//////            task.didReceive(.response(for: task.request))
//////            task.didReceive(responseData)
//////            task.didFinish()
//////        }
//////
//////        var eDidFinish = expectation(description: "onDidFinish 1")
//////        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
//////        print("load", testSchemeRequest.url!, webView.load(testSchemeRequest))
//////
//////        waitForExpectations(timeout: 1)
//////        print("did load 1", testSchemeRequest.url!)
//////
//////
//////        eDidFinish = expectation(description: "onDidFinish 2")
//////        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
//////
//////        DispatchQueue.main.async {
//////            print("load 2", self.redirectSchemeRequest.url!, self.webView.load(self.testSchemeRequest))
//////        }
//////
//////        waitForExpectations(timeout: 1)
////        performAndWaitForDidFinish { self.webView.load(self.testSchemeRequest) }
////        performAndWaitForDidFinish { self.webView.load(self.testSchemeRequest) }
////        print("did load 2", redirectSchemeRequest.url!)
////
////        let expectedNavAction = NavigationAction(navigationType: .unknown, request: self.testSchemeRequest, sourceFrame: .mainFrame(for: webView), targetFrame: .mainFrame(for: webView), shouldDownload: false)
////        let navIdentity = NavigationIdentity.autoresolvedOnFirstCompare
////        let expectedResponse = NavigationResponse(response: .response(for: testSchemeRequest), isForMainFrame: true, canShowMIMEType: true)
////        let expectedEvents: [NavigationEvent] = [
////            .navigationAction(expectedNavAction),
////            .willStart(expectedNavAction),
////            .didStart(.init(navigationAction: expectedNavAction, state: .started, identity: navIdentity)),
////            .navigationResponse(expectedResponse, .init(navigationAction: expectedNavAction, state: .responseReceived(expectedResponse), identity: navIdentity)),
////            .didCommit(.init(navigationAction: expectedNavAction, state: .responseReceived(expectedResponse), identity: navIdentity, isCommitted: true)),
////            .willFinish(.init(navigationAction: expectedNavAction, state: .awaitingFinishOrClientRedirect, identity: navIdentity, isCommitted: true)),
////            .didFinish(.init(navigationAction: expectedNavAction, state: .finished, identity: navIdentity, isCommitted: true)),
////        ]
////
////        let eDidFinish = expectation(description: "onDidFinish 3")
////        responder(at: 0).onDidFinish = { _ in
////            print("onDidFinish (2)")
//////            eDidFinish
////        }
////
////        testSchemeHandler.onRequest = { [unowned self, responseData] task in
////            print("did receive request 2")
////            task.didReceive(.response(for: task.request))
////            task.didReceive(responseData)
////            print("go back!")
////            self.webView.goBack()
////        }
////
////        DispatchQueue.main.async {
////            print("load 3", self.redirectSchemeRequest2.url!, self.webView.load(self.redirectSchemeRequest2))
////        }
////        waitForExpectations(timeout: 1)
////        print("did load", redirectSchemeRequest.url!)
////
////        assertHistoryEquals(responder(at: 0).history, expectedEvents)
////    }
////
////    func testBackNavigationInterruptingLoad_working() {
////        navigationDelegate.setResponders(.strong(NavigationResponderMock()))
////
////        testSchemeHandler.onRequest = { [responseData] task in
////            print("did receive request")
////            task.didReceive(.response(for: task.request))
////            task.didReceive(responseData)
////            task.didFinish()
////        }
////
////        var eDidFinish = expectation(description: "onDidFinish 1")
////        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
////        DispatchQueue.main.async {
////            print("load", self.testSchemeRequest.url!, self.webView.load(self.testSchemeRequest))
////        }
////        waitForExpectations(timeout: 1)
////        print("did load 1", testSchemeRequest.url!)
////
////
////        eDidFinish = expectation(description: "onDidFinish 2")
////        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
////
////        DispatchQueue.main.async {
////            print("load 2", self.redirectSchemeRequest.url!, self.webView.load(self.redirectSchemeRequest))
////        }
////
////        waitForExpectations(timeout: 1)
////        print("did load 2", redirectSchemeRequest.url!)
////
////        let expectedNavAction = NavigationAction(navigationType: .unknown, request: self.testSchemeRequest, sourceFrame: .mainFrame(for: webView), targetFrame: .mainFrame(for: webView), shouldDownload: false)
////        let navIdentity = NavigationIdentity.autoresolvedOnFirstCompare
////        let expectedResponse = NavigationResponse(response: .response(for: testSchemeRequest), isForMainFrame: true, canShowMIMEType: true)
////        let expectedEvents: [NavigationEvent] = [
////            .navigationAction(expectedNavAction),
////            .willStart(expectedNavAction),
////            .didStart(.init(navigationAction: expectedNavAction, state: .started, identity: navIdentity)),
////            .navigationResponse(expectedResponse, .init(navigationAction: expectedNavAction, state: .responseReceived(expectedResponse), identity: navIdentity)),
////            .didCommit(.init(navigationAction: expectedNavAction, state: .responseReceived(expectedResponse), identity: navIdentity, isCommitted: true)),
////            .willFinish(.init(navigationAction: expectedNavAction, state: .awaitingFinishOrClientRedirect, identity: navIdentity, isCommitted: true)),
////            .didFinish(.init(navigationAction: expectedNavAction, state: .finished, identity: navIdentity, isCommitted: true)),
////        ]
////
////        eDidFinish = expectation(description: "onDidFinish 3")
////        responder(at: 0).onDidFinish = { nav in
////            if nav.url == Self.testSchemeURL {
////                print("onDidFinish (2)")
////                eDidFinish.fulfill()
////            }
////        }
////
////        testSchemeHandler.onRequest = { [unowned self, responseData] task in
////            print("did receive request 2")
////            task.didReceive(.response(for: task.request))
////
////            DispatchQueue.main.async {
////                print("go back!", self.webView.backForwardList.backList, self.webView.goBack())
////
////            }
////
////            task.didReceive(responseData)
////            task.didFinish()
////        }
////
////        DispatchQueue.main.async {
////            print("load 3", self.redirectSchemeRequest2.url!, self.webView.load(self.redirectSchemeRequest2))
////        }
////        waitForExpectations(timeout: 10)
////        print("did load", redirectSchemeRequest.url!)
////
////        assertHistoryEquals(responder(at: 0).history, expectedEvents)
////    }
////
////    func testBackNavigationInterruptingLoad_working_frame() {
////        navigationDelegate.setResponders(.strong(NavigationResponderMock()))
////
////        testSchemeHandler.onRequest = { [responseData] task in
////            print("did receive request")
////            task.didReceive(.response(for: task.request))
////            task.didReceive(responseData)
////            task.didFinish()
////        }
////
////        var eDidFinish = expectation(description: "onDidFinish 1")
////        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
////        DispatchQueue.main.async {
////            print("load", self.testSchemeRequest.url!, self.webView.load(self.testSchemeRequest))
////        }
////        waitForExpectations(timeout: 1)
////        print("did load 1", testSchemeRequest.url!)
////
////
////        eDidFinish = expectation(description: "onDidFinish 2")
////        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
////
////        DispatchQueue.main.async {
////            print("load 2", self.redirectSchemeRequest.url!, self.webView.load(self.redirectSchemeRequest))
////        }
////
////        waitForExpectations(timeout: 1)
////        print("did load 2", redirectSchemeRequest.url!)
////
////        let expectedNavAction = NavigationAction(navigationType: .unknown, request: self.testSchemeRequest, sourceFrame: .mainFrame(for: webView), targetFrame: .mainFrame(for: webView), shouldDownload: false)
////        let navIdentity = NavigationIdentity.autoresolvedOnFirstCompare
////        let expectedResponse = NavigationResponse(response: .response(for: testSchemeRequest), isForMainFrame: true, canShowMIMEType: true)
////        let expectedEvents: [NavigationEvent] = [
////            .navigationAction(expectedNavAction),
////            .willStart(expectedNavAction),
////            .didStart(.init(navigationAction: expectedNavAction, state: .started, identity: navIdentity)),
////            .navigationResponse(expectedResponse, .init(navigationAction: expectedNavAction, state: .responseReceived(expectedResponse), identity: navIdentity)),
////            .didCommit(.init(navigationAction: expectedNavAction, state: .responseReceived(expectedResponse), identity: navIdentity, isCommitted: true)),
////            .willFinish(.init(navigationAction: expectedNavAction, state: .awaitingFinishOrClientRedirect, identity: navIdentity, isCommitted: true)),
////            .didFinish(.init(navigationAction: expectedNavAction, state: .finished, identity: navIdentity, isCommitted: true)),
////        ]
////
////        eDidFinish = expectation(description: "onDidFinish 3")
////        responder(at: 0).onDidFinish = { nav in
////            if nav.url == Self.testSchemeURL {
////                print("onDidFinish (2)")
////                eDidFinish.fulfill()
////            }
////        }
////// TODO: Test using direct nav delegate calls
////
////        testSchemeHandler.onRequest = { [unowned self, responseData] task in
////            print("did receive request \(task.request.url!)")
////
////            if task.request.url == Self.testSchemeFrameURL {
////                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
////                    print("go back!", self.webView.backForwardList.backList, self.webView.goBack())
////                }
////
////                return
////            }
////
////            task.didReceive(.response(for: task.request))
////            task.didReceive("""
////                <html><body><iframe src="\(Self.testSchemeFrameURL)" /></body></html>
////            """.data(using: .utf8)!)
////            DispatchQueue.main.async {
////                task.didFinish()
////            }
////        }
////
////        DispatchQueue.main.async {
////            print("load 3", self.redirectSchemeRequest2.url!, self.webView.load(self.redirectSchemeRequest2))
////        }
////        waitForExpectations(timeout: 10)
////        print("did load", redirectSchemeRequest.url!)
////
////        assertHistoryEquals(responder(at: 0).history, expectedEvents)
////    }
//
//    func testWhenBackNavigationInterrupted_newNavigationIsStarted() throws {
//        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
//
//        // 1. create back navigation history
//        server.middleware = [{ [data] request in
//            return .ok(.data(data.html))
//        }]
//        try server.start(8084)
//
//        let eDidFinish1 = expectation(description: "onDidFinish 1")
//        responder(at: 0).onDidFinish = { _ in eDidFinish1.fulfill() }
//        webView.load(req(urls.local1))
//        waitForExpectations(timeout: 1)
//
//        // 2. send goBack() while navigation is not yet finished (loading a frame)
//        let lock = NSLock()
//        server.middleware = [{ [urls, data] request in
//            guard request.path == urls.local2.relativePath else { return nil }
//            return .ok(.data(data.htmlWithIframe3))
//
//        }, { [urls, data] request in
//            guard request.path == urls.local3.relativePath else { fatalError() }
//
//            DispatchQueue.main.async {
//                self.webView.goBack()
//            }
//            lock.lock()
//            defer { lock.unlock() }
//
//            return .ok(.data(data.html))
//        }]
//
//        // allow back navigation; expect back navigation
//        let eOnBackNavigation = expectation(description: "onBackNavigation")
//        responder(at: 0).onNavigationAction = { action, _ in
//            if action.navigationType.isBackForward {
//                DispatchQueue.main.async {
//                    eOnBackNavigation.fulfill()
//                    lock.unlock()
//                }
//            }
//            return .allow
//        }
//
//        // expect back navigation to finish
//        let eDidFinish2 = expectation(description: "onDidFinish 2")
//        responder(at: 0).onDidFinish = { navigation in
//            if navigation.navigationAction.navigationType.isBackForward {
//                eDidFinish2.fulfill()
//            }
//        }
//
//        lock.lock()
//        webView.load(req(urls.local2))
//        waitForExpectations(timeout: 1)
//        lock.try(); lock.unlock()
//
//        assertHistoryEquals(responder(at: 0).history, [
//            .navigationAction(req(urls.local1), .other, src: main()),
//            .willStart(0),
//            .didStart(Nav(action: 0, .started)),
//            .response(Nav(action: 0, .resp(urls.local1, data.html.count))),
//            .didCommit(Nav(action: 0, .resp(urls.local1, data.html.count), .committed)),
//            .didFinish(Nav(action: 0, .finished, .committed)),
//            .navigationAction(req(urls.local2), .other, from: webView.item(at: 0), src: main(urls.local1)),
//            .willStart(1),
//            .didStart(Nav(action: 1, .started)),
//            .response(Nav(action: 1, .resp(urls.local2, data.htmlWithIframe3.count))),
//            .didCommit(Nav(action: 1, .resp(urls.local2, data.htmlWithIframe3.count), .committed)),
//            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": "http://localhost:8084/2"]), .other, from: webView.item(at: 1), src: frame(4, urls.local2), targ: frame(15, .empty, secOrigin: urls.local.securityOrigin)),
//            .didFinish(Nav(action: 1, .finished, .committed)),
//            .navigationAction(req(urls.local1, defaultHeaders + ["Upgrade-Insecure-Requests": "1"]), .backForw(-1), from: webView.item(at: 1), src: main(urls.local2)),
//            .willStart(3),
//            .didStart(Nav(action: 3, .started)),
//            .didCommit(Nav(action: 3, .started, .committed)),
//            .didFinish(Nav(action: 3, .finished, .committed))
//        ])
//    }

//
//    func testClientRedirectWithoutWillPerformClientRedirect() {
//        let handler = WillPerformClientRedirectHandler()
//        navigationDelegate.registerCustomDelegateMethodHandler(.strong(handler), for: #selector(WillPerformClientRedirectHandler.webView(_:willPerformClientRedirectTo:delay:)))
//
//        let eWillPerformClientRedirect = expectation(description: "willPerformClientRedirect")
//        handler.willPerformClientRedirectHandler = { _, _ in
//            eWillPerformClientRedirect.fulfill()
//        }
//
//        navigationDelegate.setResponders(.strong(NavigationResponderMock()))
//
//        let expectedNavAction = NavAction(navigationType: .unknown, url: Self.testSchemeURL)
//        let redirectedNavigation = EquatableNav(navigationAction: expectedNavAction, state: .redirected, isCommitted: true)
//        let redirectNavAction = NavAction(navigationType: .redirect(type: .client(delay: 0), previousNavigation: redirectedNavigation), url: Self.redirectSchemeURL)
//        let finalNavigation = EquatableNav(navigationAction: redirectNavAction, state: .started)
//        let expectedEvents: [NavigationEvent] = [
//            .navigationAction(expectedNavAction),
//            .willStart(expectedNavAction),
//            .didStart(.init(navigationAction: expectedNavAction, state: .started)),
//            .navigationResponse(.init(isForMainFrame: true, url: Self.testSchemeURL)),
//            .didCommit(.init(navigationAction: expectedNavAction, state: .responseReceived(Self.testSchemeURL), isCommitted: true)),
//            .willFinish(.init(navigationAction: expectedNavAction, state: .awaitingFinishOrClientRedirect, isCommitted: true)),
//            .navigationAction(redirectNavAction),
//            .willStart(redirectNavAction),
//            .didStart(finalNavigation),
//            .navigationResponse(.init(isForMainFrame: true, url: Self.redirectSchemeURL)),
//            .didCommit(.init(navigationAction: redirectNavAction, state: .responseReceived(Self.redirectSchemeURL), isCommitted: true)),
//            .willFinish(.init(navigationAction: redirectNavAction, state: .awaitingFinishOrClientRedirect, isCommitted: true)),
//            .didFinish(.init(navigationAction: redirectNavAction, state: .finished, isCommitted: true)),
//        ]
//
//        let eDidFinish = expectation(description: "onDidFinish")
//        responder(at: 0).onDidFinish = { _ in
//            eDidFinish.fulfill()
//        }
//
//        testSchemeHandler.onRequest = { [unowned self] task in
//            task.didReceive(.response(for: task.request))
//            if task.request.url == Self.testSchemeURL {
//                task.didReceive(self.clientRedirectData(to: Self.redirectSchemeURL))
//            } else {
//                task.didReceive(self.responseData)
//            }
//            task.didFinish()
//        }
//
//        webView.load(testSchemeRequest)
//        waitForExpectations(timeout: 1)
//
//        assertHistoryEquals(responder(at: 0).history, expectedEvents)
//    }

    func testDoubleClientRedirect() {}
    func testClientRedirectWithFakeBackAction() {}
    func testClientAndServerRedirect() {}
    func testDoubleServerAndClientRedirect() {}

    func testUserAgent() {} // test user prefs
    // TODO: test non-main-frame nav action
    // TODO: test cancelling navigation didFailNavigation
    // TODO: Task cancellation
    // TODO: targeting new window
    // TODO: session restoration/navigation to about:blank (no NavigationAction)
    // TODO: javascript Enable
    // TODO: downloads
    // TODO: downloads; DidFail called after direct download URL pasting asserting
    // TODO: Expected navigation type, different conditions
    // TODO: Reset Expected navigation type after navigation or main navigation to another domain
    // TODO: termination
    // TODO: Redirect History
    // TODO: user-initiated nav action (nav action types)
    // TODO: refresh, form submit .. action types

    func testWhenClientRedirectWithDelayAndThenNavigationIsFinished() {}
    func testWhenNavigationResponderTakesLongToReturnDecisionAndAnotherNavigationComesInBeforeIt() {}
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
