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

import Combine
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

    var currentHistoryItemIdentityCancellable: AnyCancellable!
    var history = [UInt64: HistoryItemIdentity]()

    lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(testSchemeHandler, forURLScheme: TestNavigationSchemeHandler.scheme)
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = navigationDelegateProxy
        currentHistoryItemIdentityCancellable = navigationDelegate.$currentHistoryItemIdentity.sink { [unowned self] historyItem in
            guard let historyItem, !self.history.contains(where: { $0.value == historyItem }) else { return }
            let lastNavigationAction = self.responder(at: 0).navigationActionsCache.max
            self.history[lastNavigationAction] = historyItem
        }
        
        return webView
    }()

    struct URLs {
        let https = URL(string: "https://duckduckgo.com/")!

        let testScheme = URL(string: TestNavigationSchemeHandler.scheme + "://duckduckgo.com")!

        let local = URL(string: "http://localhost:8084")!
        let local1 = URL(string: "http://localhost:8084/1")!
        let local2 = URL(string: "http://localhost:8084/2")!
        let local3 = URL(string: "http://localhost:8084/3")!
        let local4 = URL(string: "http://localhost:8084/4")!

        let localHashed = URL(string: "http://localhost:8084#")!
        let localHashed1 = URL(string: "http://localhost:8084#navlink")!
        let localHashed2 = URL(string: "http://localhost:8084#navlink2")!
        let local3Hashed = URL(string: "http://localhost:8084/3#navlink")!

        let aboutBlank = URL(string: "about:blank")!
        let aboutPrefs = URL(string: "about:prefs")!

        let post3 = URL(string: "http://localhost:8084/post3.html")!
    }
    let urls = URLs()

    struct DataSource {
        let empty = Data()
        let html = """
            <html>
                <body>
                    some data
                    <a id="navlink" />
                </body>
            </html>
        """.data(using: .utf8)!
        let htmlWithIframe3 = "<html><body><iframe src='/3' /></body></html>".data(using: .utf8)!
        let htmlWithOpenInNewWindow: Data = {
            """
                <html><body>
                <script language='JavaScript'>
                    window.open("http://localhost:8084/2", "_blank");
                </script>
                </body></html>
            """.data(using: .utf8)!
        }()

        let metaRedirect = """
        <html>
            <head>
                <meta http-equiv="Refresh" content="0; URL=http://localhost:8084/3" />
            </head>
        </html>
        """.data(using: .utf8)!
        let delayedMetaRedirect = """
        <html>
            <head>
                <meta http-equiv="Refresh" content="1; URL=http://localhost:8084/3" />
            </head>
        </html>
        """.data(using: .utf8)!

        let clientRedirectData: Data = """
            <html><body>
            <script language='JavaScript'>
                window.parent.location.replace("http://localhost:8084/3");
            </script>
            </body></html>
        """.data(using: .utf8)!

        let clientRedirectData2: Data = """
            <html><body>
            <script language='JavaScript'>
                window.parent.location.replace("http://localhost:8084/2");
            </script>
            </body></html>
        """.data(using: .utf8)!

        let sameDocumentClientRedirectData: Data = """
            <html><body>
            <script language='JavaScript'>
                window.parent.location.replace("http://localhost:8084/#navlink");
            </script>
            </body></html>
        """.data(using: .utf8)!

        let aboutPrefsInteractionStateData = Data.sessionRestorationMagic + """
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

        let aboutPrefsAfterRegularNavigationInteractionStateData = Data.sessionRestorationMagic + """
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

        let interactionStateData = Data.sessionRestorationMagic + """
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
        NavigationAction.resetIdentifier()
    }

    override func tearDown() {
        self.testSchemeHandler = nil
        server.stop()
        self.navigationDelegate.setResponders()
    }

    func responder(at index: Int) -> NavigationResponderMock! {
        navigationDelegate.responders[index] as? NavigationResponderMock
    }

    func navAct(_ idx: UInt64) -> NavAction {
        return responder(at: 0).navigationActionsCache.dict[idx]!
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
                    XCTFail(NavAction.difference(between: r1, and: r2)!)
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
        responder(at: idx).history.encoded(with: urls, webView: webView, dataSource: data, history: history)
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

        XCTAssertFalse(navAct(1).navigationAction.isTargetingNewWindow)
        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart( Nav(action: navAct(1), .started)),
            .response( Nav(action: navAct(1), .resp(urls.local, data.html.count))),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, data.html.count), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed))
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
                XCTAssertEqual(NavAction(navigationAction), navAct(1))
                XCTAssertEqual(redirect, .redirect(req(urls.local2)))
                eWillCancel.fulfill()
            }
            responder(at: i).onDidCancel = { [unowned self] navigationAction, redirect in
                XCTAssertEqual(NavAction(navigationAction), navAct(1))
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
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .resp(urls.local1, status: 404, mime: "text/plain", headers: ["Server": "Swifter Unspecified"]))),
            .didFail( Nav(action: navAct(1), .failed(WKError(.frameLoadInterruptedByPolicyChange))), WKError.Code.frameLoadInterruptedByPolicyChange.rawValue)
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 2, equalsTo: [
            .navigationAction(req(urls.local1), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .didFail( Nav(action: navAct(1), .failed(WKError(.frameLoadInterruptedByPolicyChange))), WKError.Code.frameLoadInterruptedByPolicyChange.rawValue)
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
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .didFail( Nav(action: navAct(1), .failed(WKError(NSURLErrorCannotConnectToHost))), NSURLErrorCannotConnectToHost)
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
            .willStart(navAct(1)),
            .didStart( Nav(action: navAct(1), .started)),
            .response( Nav(action: navAct(1), .resp(urls.local, data.html.count))),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, data.html.count), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed))
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 2, equalsTo: [
            .willStart(navAct(1)),
            .didStart( Nav(action: navAct(1), .started)),
            .response( Nav(action: navAct(1), .resp(urls.local, data.html.count))),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, data.html.count), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed))
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
            .willStart(navAct(1)),
            .didStart( Nav(action: navAct(1), .started)),
            .response( Nav(action: navAct(1), .resp(urls.local, data.html.count))),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, data.html.count), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed))
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 2, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart( Nav(action: navAct(1), .started)),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, data.html.count), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed))
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

        server.middleware = [{ [data] request in
            guard request.headers["authorization"] == nil else { return nil }
            return .raw(401, "Unauthorized", ["WWW-Authenticate": "Basic"]) { writer in
                try! writer.write(data.html)
            }
        }, { [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .didReceiveAuthenticationChallenge(.init("localhost", 8084, "http", realm: "localhost", method: "NSURLAuthenticationMethodHTTPBasic"), Nav(action: navAct(1), .started, nil, .gotAuth)),
            .response( Nav(action: navAct(1), .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]), nil, .gotAuth)),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]), .committed, .gotAuth)),
            .didFinish(Nav(action: navAct(1), .finished, .committed, .gotAuth))
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 2, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart( Nav(action: navAct(1), .started)),
            .response( Nav(action: navAct(1), .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]), nil, .gotAuth)),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]), .committed, .gotAuth)),
            .didFinish(Nav(action: navAct(1), .finished, .committed, .gotAuth))
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
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .didReceiveAuthenticationChallenge(.init("localhost", 8084, "http", realm: "localhost", method: "NSURLAuthenticationMethodHTTPBasic"), Nav(action: navAct(1), .started, nil, .gotAuth)),
            .response( Nav(action: navAct(1), .resp(urls.local, data.htmlWithIframe3.count), nil, .gotAuth)),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, data.htmlWithIframe3.count), .committed, .gotAuth)),
            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(4, urls.local), targ: frame(9, .empty, secOrigin: urls.local.securityOrigin)),
            .didReceiveAuthenticationChallenge(.init("localhost", 8084, "http", realm: "localhost", method: "NSURLAuthenticationMethodHTTPBasic"), Nav(action: navAct(1), .resp(urls.local, data.htmlWithIframe3.count), .committed, .gotAuth)),
            .response(.resp(resp(urls.local3, data.html.count), .nonMain), Nav(action: navAct(1), .resp(urls.local, data.htmlWithIframe3.count), .committed, .gotAuth)),
            .didFinish(Nav(action: navAct(1), .finished, .committed, .gotAuth))
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 2, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart( Nav(action: navAct(1), .started)),
            .response( Nav(action: navAct(1), .resp(urls.local, data.htmlWithIframe3.count), nil, .gotAuth)),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, data.htmlWithIframe3.count), .committed, .gotAuth)),
            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(4, urls.local), targ: frame(9, .empty, secOrigin: urls.local.securityOrigin)),
            .response(.resp(resp(urls.local3, data.html.count), .nonMain), Nav(action: navAct(1), .resp(urls.local, data.htmlWithIframe3.count), .committed, .gotAuth)),
            .didFinish(Nav(action: navAct(1), .finished, .committed, .gotAuth))
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

        server.middleware = [{ [data] request in
            guard request.headers["authorization"] == nil else { return nil }
            return .raw(401, "Unauthorized", ["WWW-Authenticate": "Basic"]) { writer in
                try! writer.write(data.html)
            }
        }]
        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .didReceiveAuthenticationChallenge(.init("localhost", 8084, "http", realm: "localhost", method: "NSURLAuthenticationMethodHTTPBasic"), Nav(action: navAct(1), .started, nil, .gotAuth)),
            .response( Nav(action: navAct(1), .resp(urls.local, status: 401, headers: ["Www-Authenticate": "Basic", "Server": "Swifter Unspecified"]), nil, .gotAuth)),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, status: 401, headers: ["Www-Authenticate": "Basic", "Server": "Swifter Unspecified"]), .committed, .gotAuth)),
            .didFinish(Nav(action: navAct(1), .finished, .committed, .gotAuth))
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

        server.middleware = [{ [data] request in
            guard request.headers["authorization"] == nil else { return nil }
            return .raw(401, "Unauthorized", ["WWW-Authenticate": "Basic"]) { writer in
                try! writer.write(data.html)
            }
        }]
        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .didReceiveAuthenticationChallenge(.init("localhost", 8084, "http", realm: "localhost", method: "NSURLAuthenticationMethodHTTPBasic"), Nav(action: navAct(1), .started, nil, .gotAuth)),
            .didFail(Nav(action: navAct(1), .failed(WKError(NSURLErrorCancelled)), nil, .gotAuth), NSURLErrorCancelled)
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 2, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .didFail(Nav(action: navAct(1), .failed(WKError(NSURLErrorCancelled)), nil, .gotAuth), NSURLErrorCancelled)
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

        server.middleware = [{ [data] request in
            guard request.headers["authorization"] == nil else { return nil }
            return .raw(401, "Unauthorized", ["WWW-Authenticate": "Basic"]) { writer in
                try! writer.write(data.html)
            }
        }]
        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .didReceiveAuthenticationChallenge(.init("localhost", 8084, "http", realm: "localhost", method: "NSURLAuthenticationMethodHTTPBasic"), Nav(action: navAct(1), .started, nil, .gotAuth)),
            .response(Nav(action: navAct(1), .resp(urls.local, status: 401, headers: ["Server": "Swifter Unspecified", "Www-Authenticate": "Basic"]), nil, .gotAuth)),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, status: 401, headers: ["Server": "Swifter Unspecified", "Www-Authenticate": "Basic"]), .committed, .gotAuth)),
            .didFinish(Nav(action: navAct(1), .finished, .committed, .gotAuth))
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 2, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .resp(urls.local, status: 401, headers: ["Server": "Swifter Unspecified", "Www-Authenticate": "Basic"]), nil, .gotAuth)),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, status: 401, headers: ["Server": "Swifter Unspecified", "Www-Authenticate": "Basic"]), .committed, .gotAuth)),
            .didFinish(Nav(action: navAct(1), .finished, .committed, .gotAuth))
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
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .resp(urls.local, status: 404, mime: "text/plain", headers: ["Server": "Swifter Unspecified"]))),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, status: 404, mime: "text/plain", headers: ["Server": "Swifter Unspecified"]), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed))
        ])
    }

    func testGoBackAfterSessionRestoration() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.string()!))
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
            .navigationAction(req(urls.local1, cachePolicy: .returnCacheDataElseLoad), .backForw(-1), from: history[1], src: main(urls.local)),
            .willStart(navAct(2)),
            .didStart( Nav(action: navAct(2), .started)),
            .response( Nav(action: navAct(2), .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: navAct(2), .finished, .committed))
        ])
    }

    func testGoForwardAfterSessionRestoration() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        var sessionState = data.interactionStateData.plist
        sessionState["SessionHistory", as: [String: Any].self]!["SessionHistoryCurrentIndex"] = 0
        webView.interactionState = Data.sessionRestorationMagic + sessionState.plist
        waitForExpectations(timeout: 1)

        let eDidFinish2 = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish2.fulfill() }

        webView.goForward()
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local1, cachePolicy: .returnCacheDataElseLoad), .restore, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed)),

            .navigationAction(req(urls.local, cachePolicy: .returnCacheDataElseLoad), .backForw(1), from: history[1], src: main(urls.local1)),
            .willStart(navAct(2)),
            .didStart(Nav(action: navAct(2), .started)),
            .response(Nav(action: navAct(2), .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: navAct(2), .finished, .committed))
        ])
    }

    func testGoBackAfterSessionRestorationCacheFailure() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let eDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { _, _ in eDidFail.fulfill() }

        // restore before server startup to raise cache failure
        webView.interactionState = data.interactionStateData
        waitForExpectations(timeout: 1)

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        var eDidFinish = expectation(description: "onDidFinish 1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        webView.goBack()
        waitForExpectations(timeout: 1)

        eDidFinish = expectation(description: "onDidFinish 2")
        webView.goForward()
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local, cachePolicy: .returnCacheDataElseLoad), .restore, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .didFail(Nav(action: navAct(1), .failed(WKError(NSURLErrorCannotConnectToHost))), NSURLErrorCannotConnectToHost),

            .navigationAction(req(urls.local1, cachePolicy: .returnCacheDataElseLoad), .backForw(-1), from: history[1], src: main()),
            .willStart(navAct(2)),
            .didStart(Nav(action: navAct(2), .started)),
            .response(Nav(action: navAct(2), .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: navAct(2), .finished, .committed)),

            .navigationAction(req(urls.local, cachePolicy: .returnCacheDataElseLoad), .backForw(1), from: history[2], src: main(urls.local1)),
            .willStart(navAct(3)),
            .didStart(Nav(action: navAct(3), .started)),
            .response(Nav(action: navAct(3), .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(3), .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: navAct(3), .finished, .committed))
        ])
    }

    func testGoForwardAfterSessionRestorationCacheFailure() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let eDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { _, _ in eDidFail.fulfill() }

        // restore before server startup to raise cache failure
        var sessionState = data.interactionStateData.plist
        sessionState["SessionHistory", as: [String: Any].self]!["SessionHistoryCurrentIndex"] = 0

        webView.interactionState = sessionState.interactionStateData
        waitForExpectations(timeout: 1)

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        var eDidFinish = expectation(description: "onDidFinish 1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        webView.goForward()
        waitForExpectations(timeout: 1)

        eDidFinish = expectation(description: "onDidFinish 2")
        webView.goBack()
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local1, cachePolicy: .returnCacheDataElseLoad), .restore, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .didFail(Nav(action: navAct(1), .failed(WKError(NSURLErrorCannotConnectToHost))), NSURLErrorCannotConnectToHost),

            .navigationAction(req(urls.local, cachePolicy: .returnCacheDataElseLoad), .backForw(1), from: history[1], src: main()),
            .willStart(navAct(2)),
            .didStart(Nav(action: navAct(2), .started)),
            .response(Nav(action: navAct(2), .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: navAct(2), .finished, .committed)),

            .navigationAction(req(urls.local1, cachePolicy: .returnCacheDataElseLoad), .backForw(-1), from: history[2], src: main(urls.local)),
            .willStart(navAct(3)),
            .didStart(Nav(action: navAct(3), .started)),
            .response(Nav(action: navAct(3), .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(3), .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: navAct(3), .finished, .committed))
        ])
    }

    func testGoBack() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        var eDidFinish = expectation(description: "onDidFinish 1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        eDidFinish = expectation(description: "onDidFinish 2")
        webView.load(req(urls.local1))
        waitForExpectations(timeout: 1)

        eDidFinish = expectation(description: "onDidFinish back")
        webView.goBack()
        waitForExpectations(timeout: 1)

        eDidFinish = expectation(description: "onDidFinish forw")
        webView.goForward()
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            // #1
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed)),
            // #2
            .navigationAction(req(urls.local1), .other, from: history[1], src: main(urls.local)),
            .willStart(navAct(2)),
            .didStart(Nav(action: navAct(2), .started)),
            .response(Nav(action: navAct(2), .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: navAct(2), .finished, .committed)),

            // #2 -> #1 back
            .navigationAction(req(urls.local, defaultHeaders + ["Upgrade-Insecure-Requests": "1"]), .backForw(-1), from: history[2], src: main(urls.local1)),
            .willStart(navAct(3)),
            .didStart(Nav(action: navAct(3), .started)),
            .didCommit(Nav(action: navAct(3), .started, .committed)),
            .didFinish(Nav(action: navAct(3), .finished, .committed)),

            // #1 -> #2 forward
            .navigationAction(req(urls.local1, defaultHeaders + ["Upgrade-Insecure-Requests": "1"]), .backForw(1), from: history[1], src: main(urls.local)),
            .willStart(navAct(4)),
            .didStart(Nav(action: navAct(4), .started)),
            .didCommit(Nav(action: navAct(4), .started, .committed)),
            .didFinish(Nav(action: navAct(4), .finished, .committed))

        ])
    }

    func testGoBackForwardAt3() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        var eDidFinish: XCTestExpectation!
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        for url in [urls.local, urls.local1, urls.local2, urls.local3, urls.local4] {
            eDidFinish = expectation(description: "onDidFinish \(url.string)")

            webView.load(req(url))
            waitForExpectations(timeout: 1)
        }

        responder(at: 0).clear()

        eDidFinish = expectation(description: "onDidFinish back")
        webView.go(to: webView.backForwardList.item(at: -3)!)
        waitForExpectations(timeout: 1)

        eDidFinish = expectation(description: "onDidFinish forw")
        webView.go(to: webView.backForwardList.item(at: 3)!)
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local1, cachePolicy: .returnCacheDataElseLoad), .backForw(-3), from: history[5], src: main(urls.local4)),
            .willStart(navAct(6)),
            .didStart( Nav(action: navAct(6), .started)),
            .response( Nav(action: navAct(6), .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(6), .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: navAct(6), .finished, .committed)),

            .navigationAction(req(urls.local4, defaultHeaders + ["Upgrade-Insecure-Requests": "1"]), .backForw(3), from: history[2], src: main(urls.local1)),
            .willStart(navAct(7)),
            .didStart( Nav(action: navAct(7), .started)),
            .didCommit(Nav(action: navAct(7), .started, .committed)),
            .didFinish(Nav(action: navAct(7), .finished, .committed))
        ])
    }

    func testGoBackInFrame() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let didFinishLoadingFrameHandler = CustomCallbacksHandler()
        navigationDelegate.registerCustomDelegateMethodHandler(.strong(didFinishLoadingFrameHandler), for: #selector(CustomCallbacksHandler.webView(_:didFinishLoadWith:in:)))
        navigationDelegate.registerCustomDelegateMethodHandler(.strong(didFinishLoadingFrameHandler), for: #selector(CustomCallbacksHandler.webView(_:didFailProvisionalLoadWith:in:with:)))

        server.middleware = [{ [data] request in
            guard request.path == "/" else { return nil }
            return .ok(.html(data.htmlWithIframe3.string()!))
        }, { [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        let eDidFinish = expectation(description: "onDidFinish 1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        var eDidFinishLoadingFrame = expectation(description: "didFinishLoadingFrame 1")
        didFinishLoadingFrameHandler.didFinishLoadingFrame = { request, frame in
            eDidFinishLoadingFrame.fulfill()
        }
        didFinishLoadingFrameHandler.didFailProvisionalLoadInFrame = { _, _, error in XCTFail("Unexpected failure \(error)") }

        webView.evaluateJavaScript("window.frames[0].location.href = '\(urls.local1.string)'")
        waitForExpectations(timeout: 1)

        eDidFinishLoadingFrame = expectation(description: "didFinishLoadingFrame back")
        webView.goBack()
        waitForExpectations(timeout: 1)

        eDidFinishLoadingFrame = expectation(description: "didFinishLoadingFrame forw")
        webView.goForward()
        waitForExpectations(timeout: 1)

        XCTAssertFalse(navAct(2).navigationAction.isTargetingNewWindow)
        XCTAssertFalse(navAct(3).navigationAction.isTargetingNewWindow)
        XCTAssertFalse(navAct(4).navigationAction.isTargetingNewWindow)
        XCTAssertFalse(navAct(5).navigationAction.isTargetingNewWindow)
        assertHistory(ofResponderAt: 0, equalsTo: [
            // #1 main nav
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .resp(urls.local, data.htmlWithIframe3.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, data.htmlWithIframe3.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            // #2 frame nav
            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(4, urls.local), targ: frame(9, .empty, secOrigin: urls.local.securityOrigin)),
            .response(.resp(urls.local3, data.html.count, headers: .default + ["Content-Type": "text/html"], .nonMain), Nav(action: navAct(1), .resp(urls.local, data.htmlWithIframe3.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed)),

            // #3 js frame nav
            .navigationAction(req(urls.local1, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(4, urls.local), targ: frame(9, urls.local3)),
            .response(.resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"], .nonMain), nil),

            // #3 -> #1 goBack in frame
            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString], cachePolicy: .returnCacheDataElseLoad), .backForw(-1), from: history[3], src: frame(9, urls.local1)),
            .response(.resp(urls.local3, data.html.count, headers: .default + ["Content-Type": "text/html"], .nonMain), nil),
            // #1 -> #3 goForward in frame
            .navigationAction(req(urls.local1, defaultHeaders + ["Referer": urls.local.separatedString], cachePolicy: .returnCacheDataElseLoad), .backForw(1), from: history[1], src: frame(9, urls.local3)),
            .response(.resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"], .nonMain), nil)
        ])
    }

    func testGoBackInFrameAfterCacheClearing() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let didFinishLoadingFrameHandler = CustomCallbacksHandler()
        navigationDelegate.registerCustomDelegateMethodHandler(.strong(didFinishLoadingFrameHandler), for: #selector(CustomCallbacksHandler.webView(_:didFinishLoadWith:in:)))
        navigationDelegate.registerCustomDelegateMethodHandler(.strong(didFinishLoadingFrameHandler), for: #selector(CustomCallbacksHandler.webView(_:didFailProvisionalLoadWith:in:with:)))

        server.middleware = [{ [data] request in
            guard request.path == "/" else { return nil }
            return .ok(.html(data.htmlWithIframe3.string()!))
        }, { [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        let eDidFinish = expectation(description: "onDidFinish 1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        webView.interactionState = data.interactionStateData
        waitForExpectations(timeout: 1)

        var eDidFinishLoadingFrame = expectation(description: "didFinishLoadingFrame 1")
        didFinishLoadingFrameHandler.didFinishLoadingFrame = { request, frame in
            eDidFinishLoadingFrame.fulfill()
        }
        didFinishLoadingFrameHandler.didFailProvisionalLoadInFrame = { _, _, error in XCTFail("Unexpected failure \(error)") }

        webView.evaluateJavaScript("window.frames[0].location.href = '\(urls.local1.string)'")
        waitForExpectations(timeout: 1)

        let expectClearCache = expectation(description: "cache cleared")
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: Date(timeIntervalSince1970: 0)) {
            expectClearCache.fulfill()
        }
        waitForExpectations(timeout: 1)

        eDidFinishLoadingFrame = expectation(description: "didFinishLoadingFrame back")
        webView.goBack()
        waitForExpectations(timeout: 1)

        let expectClearCache2 = expectation(description: "cache cleared 2")
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: Date(timeIntervalSince1970: 0)) {
            expectClearCache2.fulfill()
        }
        waitForExpectations(timeout: 1)

        eDidFinishLoadingFrame = expectation(description: "didFinishLoadingFrame forw")
        webView.goForward()
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            // #1 main nav
            .navigationAction(req(urls.local, cachePolicy: .returnCacheDataElseLoad), .restore, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .resp(urls.local, data.htmlWithIframe3.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, data.htmlWithIframe3.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            // #2 frame nav
            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(4, urls.local), targ: frame(8, .empty, secOrigin: urls.local.securityOrigin)),
            .response(.resp(urls.local3, data.html.count, headers: .default + ["Content-Type": "text/html"], .nonMain), Nav(action: navAct(1), .resp(urls.local, data.htmlWithIframe3.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed)),

            // #3 js frame nav
            .navigationAction(req(urls.local1, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(4, urls.local), targ: frame(8, urls.local3)),
            .response(.resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"], .nonMain), nil),

            // #3 -> #1 goBack in frame
            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString], cachePolicy: .returnCacheDataElseLoad), .backForw(-1), from: history[3], src: frame(8, urls.local1)),
            .response(.resp(urls.local3, data.html.count, headers: .default + ["Content-Type": "text/html"], .nonMain), nil),

            // #1 -> #3 goForward in frame
            .navigationAction(req(urls.local1, defaultHeaders + ["Referer": urls.local.separatedString], cachePolicy: .returnCacheDataElseLoad), .backForw(1), from: history[1], src: frame(8, urls.local3)),
            .response(.resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"], .nonMain), nil)
        ])
    }

    func testOpenInNewWindow() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let uiDelegate = WKUIDelegateMock()
        var newWebView: WKWebView!
        uiDelegate.createWebViewWithConfig = { [unowned navigationDelegateProxy] config, _, _ in
            newWebView = WKWebView(frame: .zero, configuration: config)
            newWebView.navigationDelegate = navigationDelegateProxy
            return newWebView
        }
        webView.uiDelegate = uiDelegate

        server.middleware = [{ [data] request in
            guard request.path == "/" else { return nil }
            return .ok(.html(data.htmlWithOpenInNewWindow.string()!))
        }, { [data, urls] request in
            guard request.path == urls.local2.path else { return nil }
            return .ok(.html(data.metaRedirect.string()!))
        }, { [data, urls] request in
            guard request.path == urls.local3.path else { return nil }
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        let eDidFinish = expectation(description: "onDidFinish")
        var counter = 0
        responder(at: 0).onDidFinish = { _ in
            counter += 1
            guard counter == 3 else { return }
            eDidFinish.fulfill()
        }

        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        XCTAssertTrue(navAct(2).navigationAction.isTargetingNewWindow)
        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .resp(urls.local, data.htmlWithOpenInNewWindow.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, data.htmlWithOpenInNewWindow.count, headers: .default + ["Content-Type": "text/html"]), .committed)),

            .navigationAction(req(urls.local2, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: main(urls.local),
                              targ: FrameInfo(frameIdentity: .init(handle: "9", webViewIdentity: WebViewIdentity(nonretainedObject: newWebView), isMainFrame: true), url: .empty, securityOrigin: urls.local.securityOrigin)),
            .willStart(navAct(2)),

            .didFinish(Nav(action: navAct(1), .finished, .committed)),

            .didStart(Nav(action: navAct(2), .started)),
            .response(Nav(action: navAct(2), .resp(urls.local2, data.metaRedirect.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), .resp(urls.local2, data.metaRedirect.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: navAct(2), .finished, .committed)),

            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local2.string]), .redirect(.client), from: history[2], redirects: [navAct(2)],
                              src: FrameInfo(frameIdentity: .init(handle: "9", webViewIdentity: WebViewIdentity(nonretainedObject: newWebView), isMainFrame: true), url: urls.local2, securityOrigin: urls.local.securityOrigin)),
            .willStart(navAct(3)),
            .didStart(Nav(action: navAct(3), redirects: [navAct(2)], .started)),
            .response(Nav(action: navAct(3), redirects: [navAct(2)], .resp(urls.local3, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(3), redirects: [navAct(2)], .resp(urls.local3, data.html.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: navAct(3), redirects: [navAct(2)], .finished, .committed))
        ])
    }

    func testGoBackWithSameDocumentNavigation() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let customCallbacksHandler = CustomCallbacksHandler()
        navigationDelegate.registerCustomDelegateMethodHandler(.strong(customCallbacksHandler), for: #selector(CustomCallbacksHandler.webView(_:navigation:didSameDocumentNavigation:)))

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        var eDidFinish = expectation(description: "#1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        responder(at: 0).onNavigationAction = { navigationAction, _ in
            XCTAssertFalse(navigationAction.isSameDocumentNavigation)
            return .allow
        }

        // #1 load URL
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        // #2 load URL#namedlink
        eDidFinish = expectation(description: "#2")
        customCallbacksHandler.didSameDocumentNavigation = { _, type in
            if type == 3 { eDidFinish.fulfill() }
        }
        webView.load(req(urls.localHashed1))
        waitForExpectations(timeout: 1)

        // #3 load URL#namedlink2
        eDidFinish = expectation(description: "#3")
        webView.evaluateJavaScript("window.location.href = '\(urls.localHashed2.string)'")
        waitForExpectations(timeout: 1)

        // #4 load URL#namedlink
        eDidFinish = expectation(description: "#4")
        webView.evaluateJavaScript("window.location.href = '\(urls.localHashed1.string)'")
        waitForExpectations(timeout: 1)

        // #4.1 go back to URL#namedlink2
        eDidFinish = expectation(description: "#4.1")
        webView.goBack()
        waitForExpectations(timeout: 1)
        // #4.2
        eDidFinish = expectation(description: "#4.2")
        webView.goBack()
        waitForExpectations(timeout: 1)
        // #4.3
        eDidFinish = expectation(description: "#4.3")
        webView.goForward()
        waitForExpectations(timeout: 1)
        // #4.4
        eDidFinish = expectation(description: "#4.4")
        webView.goForward()
        waitForExpectations(timeout: 1)

        // #5 load URL#
        eDidFinish = expectation(description: "#5")
        webView.evaluateJavaScript("window.location.href = '\(urls.localHashed.string)'")
        waitForExpectations(timeout: 1)

        // #6 load URL
        eDidFinish = expectation(description: "#6")
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        // #7 go back to URL#
        // !! here‘s the WebKit bug: no forward item will be present here
        eDidFinish = expectation(description: "#7")
        webView.goBack()
        waitForExpectations(timeout: 1)

        // #8 go back to URL#namedlink
        eDidFinish = expectation(description: "#8")
        webView.goBack()
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            // #1 load URL
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed)),

            // #2 load URL#namedlink
            .willStart(.init(req(urls.localHashed1), .other, from: history[1], src: main(urls.local))),
            // #3 load URL#namedlink2
            .willStart(.init(req(urls.localHashed2, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[2], src: main(urls.localHashed1))),
            // #3.1 load URL#namedlink
            .willStart(.init(req(urls.localHashed1, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[3], src: main(urls.localHashed2))),

            // goBack/goForward ignored for same doc decidePolicyForNavigationAction not called

            // #5 load URL#
            .willStart(.init(req(urls.localHashed, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[4], src: main(urls.localHashed1))),

            // #6 load URL
            .navigationAction(req(urls.local), .other, from: history[5], src: main(urls.localHashed)),
            .willStart(navAct(6)),
            .didStart( Nav(action: navAct(6), .started)),
            .response( Nav(action: navAct(6), .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(6), .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: navAct(6), .finished, .committed)),

            // history items replaced due to WebKit bug
            // #7 go back to URL#
            .willStart(.init(req(urls.localHashed, defaultHeaders + ["Upgrade-Insecure-Requests": "1"]), .backForw(-1), from: history[6], src: main(urls.local))),
            // #8 go back to URL#namedlink
            .willStart(.init(req(urls.localHashed, defaultHeaders + ["Upgrade-Insecure-Requests": "1"]), .backForw(-1), from: history[7], src: main(urls.localHashed))),
        ])
    }

    func testClientRedirectToSameDocument() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let customCallbacksHandler = CustomCallbacksHandler()
        navigationDelegate.registerCustomDelegateMethodHandler(.strong(customCallbacksHandler), for: #selector(CustomCallbacksHandler.webView(_:navigation:didSameDocumentNavigation:)))

        server.middleware = [{ [data] request in
            return .ok(.html(data.sameDocumentClientRedirectData.string()!))
        }]
        try server.start(8084)

        let eDidFinish = expectation(description: "#1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        responder(at: 0).onNavigationAction = { navigationAction, _ in
            XCTAssertFalse(navigationAction.isSameDocumentNavigation)
            return .allow
        }

        let eDidSameDocumentNavigation = expectation(description: "#2")
        customCallbacksHandler.didSameDocumentNavigation = { _, type in
            if type == 3 { eDidSameDocumentNavigation.fulfill() }
        }

        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .resp(urls.local, data.sameDocumentClientRedirectData.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, data.sameDocumentClientRedirectData.count, headers: .default + ["Content-Type": "text/html"]), .committed)),

            .willStart(.init(req(urls.localHashed1, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: main(urls.local))),

            .didFinish(Nav(action: navAct(1), .finished, .committed))
        ])
    }

    func testClientRedirectFromHashedUrlToNonHashedUrl() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        var counter = 0
        server.middleware = [{ [data] request in
            counter += 1
            if counter == 1 {
                return .ok(.html(data.clientRedirectData.string()!))
            } else {
                return .ok(.html(data.html.string()!))
            }
        }]
        try server.start(8084)

        var eDidFinish = expectation(description: "#1")
        let eDidFinish2 = expectation(description: "#2")
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
            eDidFinish = eDidFinish2
        }
        responder(at: 0).onNavigationAction = { navigationAction, _ in
            XCTAssertFalse(navigationAction.isSameDocumentNavigation)
            return .allow
        }

        webView.load(req(urls.local3Hashed))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local3Hashed), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .resp(urls.local3Hashed, data.clientRedirectData.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .resp(urls.local3Hashed, data.clientRedirectData.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed)),

            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local3.string]), .redirect(.client), from: history[1], redirects: [navAct(1)], src: main(urls.local3Hashed)),
            .willStart(navAct(2)),
            .didStart(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .resp(urls.local3, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .resp(urls.local3, data.html.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, .committed))
        ])
    }

    func testReload() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        var eDidFinish = expectation(description: "didFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        responder(at: 0).clear()
        eDidFinish = expectation(description: "didReload")
        webView.reload()
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local, defaultHeaders + ["Upgrade-Insecure-Requests": "1"], cachePolicy: .reloadIgnoringLocalCacheData), .reload, from: history[1], src: main(urls.local)),
            .willStart(navAct(2)),
            .didStart( Nav(action: navAct(2), .started)),
            .response( Nav(action: navAct(2), .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: navAct(2), .finished, .committed))
        ])
    }

    func testReloadAfterSameDocumentNavigation() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let customCallbacksHandler = CustomCallbacksHandler()
        navigationDelegate.registerCustomDelegateMethodHandler(.strong(customCallbacksHandler), for: #selector(CustomCallbacksHandler.webView(_:navigation:didSameDocumentNavigation:)))

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        var eDidFinish = expectation(description: "#1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        responder(at: 0).onNavigationAction = { navigationAction, _ in
            XCTAssertFalse(navigationAction.isSameDocumentNavigation)
            return .allow
        }

        // #1 load URL
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        // #2 load URL#namedlink
        eDidFinish = expectation(description: "#2")
        customCallbacksHandler.didSameDocumentNavigation = { _, type in
            if type == 3 { eDidFinish.fulfill() }
        }
        webView.load(req(urls.localHashed1))
        waitForExpectations(timeout: 1)

        responder(at: 0).clear()
        eDidFinish = expectation(description: "didReload")
        let eNavAction = expectation(description: "onNavigationAction")
        responder(at: 0).onNavigationAction = { navigationAction, _ in
            XCTAssertFalse(navigationAction.isSameDocumentNavigation)
            eNavAction.fulfill()
            return .allow
        }
        webView.reload()
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.localHashed1, defaultHeaders + ["Upgrade-Insecure-Requests": "1"], cachePolicy: .reloadIgnoringLocalCacheData), .reload, from: history[2], src: main(urls.localHashed1)),
            .willStart(navAct(3)),
            .didStart( Nav(action: navAct(3), .started)),
            .response( Nav(action: navAct(3), .resp(urls.localHashed1, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(3), .resp(urls.localHashed1, data.html.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: navAct(3), .finished, .committed))
        ])
    }

    func testWhenAboutPrefsSessionIsRestored_navigationTypeIsSessionRestoration() {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        webView.interactionState = data.aboutPrefsAfterRegularNavigationInteractionStateData
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .willStart(.init(req(urls.aboutBlank, [:], cachePolicy: .returnCacheDataElseLoad), .restore, src: main())),
            .didStart(Nav(action: navAct(1), .started)),
            .didCommit(Nav(action: navAct(1), .started, .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed))
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
            .didStart( Nav(action: navAct(1), .started)),
            .didCommit(Nav(action: navAct(1), .started, .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed))
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
            .willStart(navAct(1)),
            .didStart( Nav(action: navAct(1), .started)),
            .response( Nav(action: navAct(1), .resp(urls.local, data.html.count))),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, data.html.count), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed)),

            .navigationAction(req(urls.aboutBlank), .other, from: history[1], src: main(urls.local)),
            .willStart(navAct(2)),
            .didStart( Nav(action: navAct(2), .started)),
            .didCommit(Nav(action: navAct(2), .started, .committed)),
            .didFinish(Nav(action: navAct(2), .finished, .committed))
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
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),

            .navigationAction(req(urls.local2, defaultHeaders + ["Upgrade-Insecure-Requests": "1", "Accept-Encoding": "gzip, deflate", "Accept-Language": "en-XX,en;q=0.9"]), .redirect(.server), redirects: [navAct(1)], src: main()),
            .willStart(navAct(2)),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),

            .navigationAction(req(urls.local3, defaultHeaders + ["Accept-Encoding": "gzip, deflate", "Accept-Language": "en-GB,en;q=0.9", "Upgrade-Insecure-Requests": "1"]), .redirect(.server), redirects: [navAct(1), navAct(2)], src: main()),
            .willStart(navAct(3)),
            .didReceiveRedirect(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .started)),

            .response( Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .resp(urls.local3, data.html.count))),
            .didCommit(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .resp(urls.local3, data.html.count), .committed)),
            .didFinish(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .finished, .committed))
        ])
    }

    func testRefreshHeaderRedirect() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        var eDidFinish = expectation(description: "onDidFinish")
        let eDidFinish2 = expectation(description: "onDidFinish2")
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
            eDidFinish = eDidFinish2
        }

        server.middleware = [{ [urls, data] request in
            switch request.path {
            case urls.local2.path:
                return .ok(.data(data.html))
            default:
                return .raw(200, "OK", ["refresh": "1; url=" + urls.local2.path]) { writer in
                    try! writer.write(data.empty)
                }
            }
        }]
        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .resp(urls.local, mime: "text/plain", headers: ["Refresh": "1; url=/2", "Server": "Swifter Unspecified"]))),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, mime: "text/plain", headers: ["Refresh": "1; url=/2", "Server": "Swifter Unspecified"]), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed)),

            .navigationAction(req(urls.local2, defaultHeaders + ["Referer": urls.local.separatedString]), .redirect(.client(delay: 1.0)), from: history[1], redirects: [navAct(1)], src: main(urls.local)),
            .willStart(navAct(2)),
            .didStart(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .resp(urls.local2, data.html.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .resp(urls.local2, data.html.count), .committed)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, .committed))
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
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),

            .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Language": "en-XX,en;q=0.9", "Upgrade-Insecure-Requests": "1", "Accept-Encoding": "gzip, deflate"]), .redirect(.server), redirects: [navAct(1)], src: main()),
            .willStart(navAct(2)),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),

            .response(Nav(action: navAct(2), redirects: [navAct(1)], .resp(urls.local2, data.metaRedirect.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .resp(urls.local2, data.metaRedirect.count), .committed)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, .committed)),

                .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local2.string]), .redirect(.client), from: history[2], redirects: [navAct(1), navAct(2)], src: main(urls.local2)),
            .willStart(navAct(3)),
            .didStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .started)),

            .navigationAction(req(urls.local4, defaultHeaders + ["Accept-Encoding": "gzip, deflate", "Upgrade-Insecure-Requests": "1", "Accept-Language": "en-GB,en;q=0.9", "Referer": urls.local2.string]), .redirect(.server), from: history[2], redirects: [navAct(1), navAct(2), navAct(3)], src: main(urls.local2)),
            .willStart(navAct(4)),
            .didReceiveRedirect(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .started)),

            .response(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .resp(urls.local4, data.html.count))),
            .didCommit(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .resp(urls.local4, data.html.count), .committed)),
            .didFinish(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .finished, .committed))
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
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),

            .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Language": "en-GB,en;q=0.9", "Upgrade-Insecure-Requests": "1", "Accept-Encoding": "gzip, deflate"]), .redirect(.server), redirects: [navAct(1)], src: main()),
            .willStart(navAct(2)),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),

            .response(Nav(action: navAct(2), redirects: [navAct(1)], .resp(urls.local2, data.metaRedirect.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .resp(urls.local2, data.metaRedirect.count), .committed)),

            .navigationAction(req(urls.local3, defaultHeaders + ["Referer":urls.local2.string]), .redirect(.client), from: history[2], redirects: [navAct(1), navAct(2)], src: main(urls.local2)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, .committed)),

            .willStart(navAct(3)),
            .didStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .started)),

            .navigationAction(req(urls.local4, defaultHeaders + ["Accept-Encoding": "gzip, deflate", "Upgrade-Insecure-Requests": "1", "Accept-Language": "en-GB,en;q=0.9", "Referer": urls.local2.string]), .redirect(.server), from: history[2], redirects: [navAct(1), navAct(2), navAct(3)], src: main(urls.local2)),
            .willStart(navAct(4)),
            .didReceiveRedirect(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .started)),

            .response(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .resp(urls.local4, data.html.count))),
            .didCommit(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .resp(urls.local4, data.html.count), .committed)),
            .didFinish(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .finished, .committed))
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
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),

            .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Language": "en-GB,en;q=0.9", "Upgrade-Insecure-Requests": "1", "Accept-Encoding": "gzip, deflate"]), .redirect(.server), redirects: [navAct(1)], src: main()),
            .willStart(navAct(2)),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),

            .response(Nav(action: navAct(2), redirects: [navAct(1)], .resp(urls.local2, data.metaRedirect.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .resp(urls.local2, data.metaRedirect.count), .committed)),

            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local2.string]), .redirect(.client), from: history[2], redirects: [navAct(1), navAct(2)], src: main(urls.local2)),
            .willStart(navAct(3)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, .committed)),

            .didStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .started)),

            .navigationAction(req(urls.local4, defaultHeaders + ["Accept-Encoding": "gzip, deflate", "Upgrade-Insecure-Requests": "1", "Accept-Language": "en-GB,en;q=0.9", "Referer": urls.local2.string]), .redirect(.server), from: history[2], redirects: [navAct(1), navAct(2), navAct(3)], src: main(urls.local2)),
            .willStart(navAct(4)),
            .didReceiveRedirect(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .started)),

            .response(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .resp(urls.local4, data.html.count))),
            .didCommit(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .resp(urls.local4, data.html.count), .committed)),
            .didFinish(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .finished, .committed))
        ])
    }

    func testClientRedirect() throws {
        navigationDelegateProxy.finishEventsDispatchTime = .afterWillStartNavigationAction
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        var counter = 0
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in
            counter += 1
            guard counter == 3 else { return }
            eDidFinish.fulfill()
        }

        server.middleware = [{ [data] request in
            guard request.path == "/" else { return nil }
            return .ok(.html(data.clientRedirectData.string()!))
        }, { [urls, data] request in
            guard request.path == urls.local3.path else { return nil }
            return .ok(.html(data.clientRedirectData2.string()!))
        }, { [data] request in
            return .ok(.data(data.html))
        }]
        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .resp(urls.local, data.clientRedirectData.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, data.clientRedirectData.count, headers: .default + ["Content-Type": "text/html"]), .committed)),

            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .redirect(.client), from: history[1], redirects: [navAct(1)], src: main(urls.local)),
            .willStart(navAct(2)),
            .didFinish(Nav(action: navAct(1), .finished, .committed)),

            .didStart(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .resp(urls.local3, data.clientRedirectData.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .resp(urls.local3, data.clientRedirectData.count, headers: .default + ["Content-Type": "text/html"]), .committed)),

            .navigationAction(req(urls.local2, defaultHeaders + ["Referer": urls.local3.string]), .redirect(.client), from: history[1], redirects: [navAct(1), navAct(2)], src: main(urls.local3)),
            .willStart(navAct(3)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, .committed)),

            .didStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .started)),
            .response(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .resp(urls.local2, data.html.count))),
            .didCommit(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .resp(urls.local2, data.html.count), .committed)),
            .didFinish(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .finished, .committed))
        ])
    }
    
    func testWhenClientRedirectWithDelay() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish1 = expectation(description: "onDidFinish 1")
        let eDidFinish2 = expectation(description: "onDidFinish 2")
        var eDidFinish = eDidFinish1
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
            eDidFinish = eDidFinish2
        }

        server.middleware = [{ [data] request in
            guard request.path == "/" else { return nil }
            return .ok(.html(data.delayedMetaRedirect.string()!))
        }, { [data] request in
            return .ok(.data(data.html))
        }]
        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .resp(urls.local, data.metaRedirect.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, data.metaRedirect.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed)),

            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .redirect(.client(delay: 1.0)), from: history[1], redirects: [navAct(1)], src: main(urls.local)),
            .willStart(navAct(2)),
            .didStart(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .resp(urls.local3, data.html.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .resp(urls.local3, data.html.count), .committed)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, .committed))
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
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),

            .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Language": "en-GB,en;q=0.9", "Upgrade-Insecure-Requests": "1", "Accept-Encoding": "gzip, deflate"]), .redirect(.server), redirects: [navAct(1)], src: main()),
            .willStart(navAct(2)),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),

            .response(Nav(action: navAct(2), redirects: [navAct(1)], .resp(urls.local2, data.metaRedirect.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .resp(urls.local2, data.metaRedirect.count), .committed)),

            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local2.string]), .redirect(.client), from: history[2], redirects: [navAct(1), navAct(2)], src: main(urls.local2)),
            .willStart(navAct(3)),
            .didStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .started)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, .committed)),

            .navigationAction(req(urls.local4, defaultHeaders + ["Accept-Encoding": "gzip, deflate", "Upgrade-Insecure-Requests": "1", "Accept-Language": "en-GB,en;q=0.9", "Referer": urls.local2.string]), .redirect(.server), from: history[2], redirects: [navAct(1), navAct(2), navAct(3)], src: main(urls.local2)),
            .willStart(navAct(4)),
            .didReceiveRedirect(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .started)),

            .response(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .resp(urls.local4, data.html.count))),
            .didCommit(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .resp(urls.local4, data.html.count), .committed)),
            .didFinish(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .finished, .committed))
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
        waitForExpectations(timeout: 1)

        var expected: [NavigationEvent] =  [

            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Language": "en-GB,en;q=0.9", "Upgrade-Insecure-Requests": "1", "Accept-Encoding": "gzip, deflate"]), .redirect(.server), redirects: [navAct(1)], src: main()),
            .willStart(navAct(2)),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            // .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1), navAct(2)...], .started)),

            .response(Nav(action: navAct(2), redirects: [navAct(1)] + .init(repeating: navAct(2), count: 9), .resp(urls.local2, data.html.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)] + .init(repeating: navAct(2), count: 9), .resp(urls.local2, data.html.count), .committed)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)] + .init(repeating: navAct(2), count: 9), .finished, .committed))
        ]
        while expected[expected.count - 4].redirectEvent!.redirects.count < 10 {
            expected.insert(.didReceiveRedirect(Nav(action: navAct(2),
                                                    redirects: [navAct(1)]
                                                    + .init(repeating: navAct(2), count: expected[expected.count - 4].redirectEvent!.redirects.count),
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
        waitForExpectations(timeout: 1)

        var expected: [NavigationEvent] =  [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),

            .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Language": "en-GB,en;q=0.9", "Upgrade-Insecure-Requests": "1", "Accept-Encoding": "gzip, deflate"]), .redirect(.server), redirects: [navAct(1)], src: main()),
            .willStart(navAct(2)),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            // ...didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1), navAct(2)...], .started)

            .didFail(Nav(action: navAct(2), redirects: [navAct(1)] + .init(repeating: navAct(2), count: 19), .failed(WKError(NSURLErrorHTTPTooManyRedirects))), NSURLErrorHTTPTooManyRedirects)
        ]
        while expected[expected.count - 2].redirectEvent!.redirects.count < 20 {
            expected.insert(.didReceiveRedirect(Nav(action: navAct(2),
                                                    redirects: [navAct(1)]
                                                        + .init(repeating: navAct(2), count: expected[expected.count - 2].redirectEvent!.redirects.count),
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
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .resp(urls.testScheme, status: nil, data.html.count))),
            .didCommit(Nav(action: navAct(1), .resp(urls.testScheme, status: nil, data.html.count), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed))
        ])
    }

    func testSimulatedRequest() {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        webView.loadSimulatedRequest(req(urls.https), responseHTML: String(data: data.html, encoding: .utf8)!)
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.https), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .didCommit(Nav(action: navAct(1), .started, .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed))
        ])
    }

    func testSimulatedRequestAfterCustomSchemeRequest() {
        navigationDelegateProxy.finishEventsDispatchTime = .instant
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
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .didFail(Nav(action: navAct(1), .failed(WKError(NSURLErrorCancelled))), NSURLErrorCancelled),

            .navigationAction(req(urls.https), .other, src: main()),
            .willStart(navAct(2)),
            .didStart(Nav(action: navAct(2), .started)),
            .didCommit(Nav(action: navAct(2), .started, .committed)),
            .didFinish(Nav(action: navAct(2), .finished, .committed))
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
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),

            .navigationAction(req(urls.https), .other, src: main()),
            .didFail(Nav(action: navAct(1), .failed(WKError(NSURLErrorCancelled))), NSURLErrorCancelled),

            .willStart(navAct(2)),
            .didStart(Nav(action: navAct(2), .started)),
            .didCommit(Nav(action: navAct(2), .started, .committed)),
            .didFinish(Nav(action: navAct(2), .finished, .committed))
        ])
    }

    func testSimulatedRequestAfterCustomSchemeRequestWithFailureAfterWillStartNavigation() {
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
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),

            .navigationAction(req(urls.https), .other, src: main()),
            .willStart(navAct(2)),
            .didFail(Nav(action: navAct(1), .failed(WKError(NSURLErrorCancelled))), NSURLErrorCancelled),

            .didStart(Nav(action: navAct(2), .started)),
            .didCommit(Nav(action: navAct(2), .started, .committed)),
            .didFinish(Nav(action: navAct(2), .finished, .committed))
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
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),

            .navigationAction(req(urls.https), .other, src: main()),
            .willStart(navAct(2)),
            .didStart(Nav(action: navAct(2), .started)),
            .didFail(Nav(action: navAct(1), .failed(WKError(NSURLErrorCancelled))), NSURLErrorCancelled),
            .didCommit(Nav(action: navAct(2), .started, .committed)),
            .didFinish(Nav(action: navAct(2), .finished, .committed))
        ])
    }

    func testRealRequestAfterCustomSchemeRequest() {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        testSchemeHandler.onRequest = { [data, urls] task in
            task.didReceive(.response(for: req(urls.local1)))
            task.didReceive(data.html)
            task.didFinish()
        }
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        webView.load(req(urls.testScheme))

        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.testScheme), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .resp(urls.local1, status: nil, data.empty.count))),
            .didCommit(Nav(action: navAct(1), .resp(urls.local1, status: nil, data.empty.count), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed))
        ])
    }

    func testStopLoadingBeforeWillStart() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]
        try server.start(8084)

        let eStopped = expectation(description: "loading stopped")
        responder(at: 0).onNavigationAction = { [unowned webView] _, _ in
            webView.stopLoading()
            eStopped.fulfill()
            return .next
        }

        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1))
        ])
    }

    func testStopLoadingAfterWillStart() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]
        try server.start(8084)

        responder(at: 0).onWillStart = { [unowned webView] _ in
            DispatchQueue.main.async {
                webView.stopLoading()
            }
        }
        let eDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { _, _ in eDidFail.fulfill() }

        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .didFail(Nav(action: navAct(1), .failed(WKError(NSURLErrorCancelled))), NSURLErrorCancelled)
        ])
    }

    func testStopLoadingAfterDidStart() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]
        try server.start(8084)

        responder(at: 0).onDidStart = { [unowned webView] _ in
            webView.stopLoading()
        }
        let eDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { _, _ in eDidFail.fulfill() }

        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .didFail(Nav(action: navAct(1), .failed(WKError(NSURLErrorCancelled))), NSURLErrorCancelled)
        ])
    }

    func testStopLoadingAfterResponse() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]
        try server.start(8084)

        responder(at: 0).onNavigationResponse = { [unowned webView] _, _ in
            webView.stopLoading()
            return .next
        }
        let eDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { _, _ in eDidFail.fulfill() }
        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .resp(urls.local, data.html.count))),
            .didFail(Nav(action: navAct(1), .failed(WKError(.frameLoadInterruptedByPolicyChange))), WKError.Code.frameLoadInterruptedByPolicyChange.rawValue)
        ])
    }

//    func testNewUserInitiatedRequestWhileCustomSchemeRequestInProgress() {
//
//    }

    // TODO: Test simulated request after normal request
    // TODO: Test custom scheme session restoration

    // TODO: Test loading interruption by new request

    // TODO: test goBack interrupting load after didCommit
    // TODO: test goBack to same document interrupting load before didCommit

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

    // TODO: matching custom nav actions
    // TODO: form submit .. action types
    func testDoubleClientRedirect() {}
    func testClientRedirectWithFakeBackAction() {}

    @MainActor
    func testNavigationActionPreferences() {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let navAction = WKNavigationActionMock(sourceFrame: .mock(for: webView), targetFrame: nil, navigationType: .other, request: req(urls.local)).navigationAction

        responder(at: 0).onNavigationAction = { _, prefs in
            prefs.userAgent = "1"
            prefs.contentMode = .mobile
            prefs.javaScriptEnabled = false
            return .cancel(with: .other(.init()))
        }
        var e = expectation(description: "decisionHandler1 called")
        navigationDelegate.webView(webView, decidePolicyFor: navAction, preferences: WKWebpagePreferences()) { [unowned webView] _, prefs in
            XCTAssertEqual(webView.customUserAgent, "")
            XCTAssertTrue(prefs.allowsContentJavaScript)
            XCTAssertEqual(prefs.preferredContentMode, .recommended)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)

        responder(at: 0).onNavigationAction = { _, prefs in
            prefs.userAgent = "allow_ua"
            prefs.contentMode = .mobile
            prefs.javaScriptEnabled = false
            return .allow
        }
        e = expectation(description: "decisionHandler2 called")
        navigationDelegate.webView(webView, decidePolicyFor: navAction, preferences: WKWebpagePreferences()) { [unowned webView] _, prefs in
            XCTAssertEqual(webView.customUserAgent, "allow_ua")
            XCTAssertFalse(prefs.allowsContentJavaScript)
            XCTAssertEqual(prefs.preferredContentMode, .mobile)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)

        responder(at: 0).onNavigationAction = { _, prefs in
            prefs.userAgent = nil
            return .allow
        }
        e = expectation(description: "decisionHandler3 called")
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false
        prefs.preferredContentMode = .desktop
        navigationDelegate.webView(webView, decidePolicyFor: navAction, preferences: prefs) { [unowned webView] _, prefs in
            XCTAssertEqual(webView.customUserAgent, "allow_ua")
            XCTAssertFalse(prefs.allowsContentJavaScript)
            XCTAssertEqual(prefs.preferredContentMode, .desktop)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)

        responder(at: 0).onNavigationAction = { _, prefs in
            prefs.userAgent = "download_ua"
            prefs.contentMode = .mobile
            prefs.javaScriptEnabled = false
            return .download
        }
        e = expectation(description: "decisionHandler4 called")
        navigationDelegate.webView(webView, decidePolicyFor: navAction, preferences: WKWebpagePreferences()) { [unowned webView] _, prefs in
            XCTAssertEqual(webView.customUserAgent, "allow_ua")
            XCTAssertTrue(prefs.allowsContentJavaScript)
            XCTAssertEqual(prefs.preferredContentMode, .recommended)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)

        responder(at: 0).onNavigationAction = { _, prefs in
            prefs.userAgent = "next_ua"
            prefs.contentMode = .mobile
            prefs.javaScriptEnabled = false
            return .next
        }
        e = expectation(description: "decisionHandler5 called")
        navigationDelegate.webView(webView, decidePolicyFor: navAction, preferences: WKWebpagePreferences()) { [unowned webView] _, prefs in
            XCTAssertEqual(webView.customUserAgent, "next_ua")
            XCTAssertFalse(prefs.allowsContentJavaScript)
            XCTAssertEqual(prefs.preferredContentMode, .mobile)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testDownloadNavigationAction() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        let eDidFinish = expectation(description: "onDidFinish")

        responder(at: 0).onNavigationAction = { _, params in
            return .download
        }
        responder(at: 0).onNavActionBecameDownload = { _, _ in
            eDidFinish.fulfill()
        }

        webView.load(URLRequest(url: urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .navActionWillBecomeDownload(navAct(1)),
            .navActionBecameDownload(navAct(1), urls.local)
        ])
    }

    func testDownloadNavigationActionFromFrame() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            guard request.path == "/" else { return nil }
            return .ok(.html(data.htmlWithIframe3.string()!))
        }, { [data, urls] request in
            guard request.path == urls.local3.path else { return nil }
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onNavigationAction = { [urls] navAction, _ in
            if navAction.url.path == urls.local3.path {
                return .download
            }
            return .next
        }
        responder(at: 0).onNavActionBecameDownload = { _, _ in
            eDidFinish.fulfill()
        }

        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .resp(urls.local, data.htmlWithIframe3.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .resp(urls.local, data.htmlWithIframe3.count, headers: .default + ["Content-Type": "text/html"]), .committed)),

            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(4, urls.local), targ: frame(9, .empty, secOrigin: urls.local.securityOrigin)),
            .navActionWillBecomeDownload(navAct(2)),

            .didFinish(Nav(action: navAct(1), .finished, .committed)),
            .navActionBecameDownload(navAct(2), urls.local3)
        ])
    }

    func testDownloadNavigationResponse() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data, urls] request in
            guard request.path == "/" else { return nil }
            return .raw(301, "Moved", ["Location": urls.local2.path]) { writer in
                try! writer.write(data.empty)
            }
        }, { [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        responder(at: 0).onNavigationAction = { _, params in
            return .allow
        }
        responder(at: 0).onNavigationResponse = { _, _ in
            .download
        }
        let eDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { _, _ in
            eDidFail.fulfill()
        }

        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(navAct(1)),
            .didStart(Nav(action: navAct(1), .started)),
            .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Encoding": "gzip, deflate", "Accept-Language": "en-XX,en;q=0.9", "Upgrade-Insecure-Requests": "1"]), .redirect(.server), redirects: [navAct(1)], src: main()),
            .willStart(navAct(2)),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .resp(urls.local2, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .navResponseWillBecomeDownload(0),
            .navResponseBecameDownload(0, urls.local2),
            .didFail(Nav(action: navAct(2), redirects: [navAct(1)], .failed(WKError(.frameLoadInterruptedByPolicyChange))), WKError.Code.frameLoadInterruptedByPolicyChange.rawValue)
        ])
    }

    func testDownloadNavigationResponseFromFrame() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let didFinishLoadingFrameHandler = CustomCallbacksHandler()
        navigationDelegate.registerCustomDelegateMethodHandler(.strong(didFinishLoadingFrameHandler), for: #selector(CustomCallbacksHandler.webView(_:didFinishLoadWith:in:)))
        navigationDelegate.registerCustomDelegateMethodHandler(.strong(didFinishLoadingFrameHandler), for: #selector(CustomCallbacksHandler.webView(_:didFailProvisionalLoadWith:in:with:)))

        server.middleware = [{ [data] request in
            guard request.path == "/" else { return nil }
            return .ok(.html(data.htmlWithIframe3.string()!))
        }, { [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        let eDidFinish = expectation(description: "onDidFinish 1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        webView.load(req(urls.local))
        waitForExpectations(timeout: 1)

        responder(at: 0).onNavigationResponse = { _, _ in
            .download
        }
        let eDidFailLoadingFrame = expectation(description: "didFailLoadingFrame")
        didFinishLoadingFrameHandler.didFailProvisionalLoadInFrame = { request, frame, _ in
            eDidFailLoadingFrame.fulfill()
        }
        responder(at: 0).clear()
        webView.evaluateJavaScript("window.frames[0].location.href = '\(urls.local1.string)'")
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local1, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(4, urls.local), targ: frame(9, urls.local3)),
            .response(.resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"], .nonMain), nil),
            .navResponseWillBecomeDownload(2),
            .navResponseBecameDownload(2, urls.local1)
        ])
    }

    // TODO: Expected navigation type, different conditions, user-initiated nav action
    // TODO: Reset Expected navigation type after navigation or main navigation to another domain
    // TODO: termination
    // TODO: js history manipulation
    // TODO: didFail non-provisional navigation

    func testWhenNavigationResponderTakesLongToReturnDecisionAndAnotherNavigationComesInBeforeIt() {}
}

private final class CustomCallbacksHandler: NSObject, NavigationResponder {

    var willPerformClientRedirectHandler: ((URL, TimeInterval) -> Void)?
    @objc(_webView:willPerformClientRedirectToURL:delay:)
    func webView(_ webView: WKWebView, willPerformClientRedirectTo url: URL, delay: TimeInterval) {
        self.willPerformClientRedirectHandler?(url, delay)
    }

    var didFinishLoadingFrame: ((URLRequest, WKFrameInfo) -> Void)?
    @objc(_webView:didFinishLoadWithRequest:inFrame:)
    func webView(_ webView: WKWebView, didFinishLoadWith request: URLRequest, in frame: WKFrameInfo) {
        print("_webView:", webView, "didFinishLoadWithRequest:", request, "inFrame:", frame)
        self.didFinishLoadingFrame?(request, frame)
    }

    var didFailProvisionalLoadInFrame: ((URLRequest, WKFrameInfo, Error) -> Void)?
    @objc(_webView:didFailProvisionalLoadWithRequest:inFrame:withError:)
    func webView(_ webView: WKWebView, didFailProvisionalLoadWith request: URLRequest, in frame: WKFrameInfo, with error: Error) {
        print("_webView:", webView, "didFailProvisionalLoadWithRequest:", request, "inFrame:", frame, "withError:", error)
        self.didFailProvisionalLoadInFrame?(request, frame, error)
    }

    var didSameDocumentNavigation: ((WKNavigation, Int) -> Void)?
    @objc(_webView:navigation:didSameDocumentNavigation:)
    func webView(_ webView: WKWebView, navigation: WKNavigation, didSameDocumentNavigation navigationType: Int) {
        print("_webView:", webView, "navigation:", navigation, "didSameDocumentNavigation:", navigationType)
        self.didSameDocumentNavigation?(navigation, navigationType)
    }

}

class WKUIDelegateMock: NSObject, WKUIDelegate {
    var createWebViewWithConfig: ((WKWebViewConfiguration, WKNavigationAction, WKWindowFeatures) -> WKWebView?)?
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        createWebViewWithConfig?(configuration, navigationAction, windowFeatures)
    }
}

private extension URLResponse {
    static func response(for request: URLRequest, mimeType: String? = "text/html", expectedLength: Int = 0, encoding: String? = nil) -> URLResponse {
        return URLResponse(url: request.url!, mimeType: mimeType, expectedContentLength: expectedLength, textEncodingName: encoding)
    }
}
