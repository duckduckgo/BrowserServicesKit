//
//  DistributedNavigationDelegateTestsHelpers.swift
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

@available(macOS 12.0, *)
class DistributedNavigationDelegateTestsBase: XCTestCase {

    var navigationDelegateProxy: NavigationDelegateProxy!

    var navigationDelegate: DistributedNavigationDelegate { navigationDelegateProxy.delegate }
    var testSchemeHandler: TestNavigationSchemeHandler! = TestNavigationSchemeHandler()
    var server: HttpServer!

    var currentHistoryItemIdentityCancellable: AnyCancellable!
    var history = [UInt64: HistoryItemIdentity]()

    var _webView: WKWebView!
    var webView: WKWebView {
        if let _webView { return _webView }

        let webView = makeWebView()
        _webView = webView
        return webView
    }
    var usedWebViews = [WKWebView]()
    var usedDelegates = [NavigationDelegateProxy]()

    let data = DataSource()
    let urls = URLs()

    override func setUp() {
        NavigationAction.resetIdentifier()
        server = HttpServer()
        navigationDelegateProxy = DistributedNavigationDelegateTests.makeNavigationDelegateProxy()
    }

    override func tearDown() {
        self.testSchemeHandler = nil
        server.stop()
        self.navigationDelegate.responders.forEach { ($0 as! NavigationResponderMock).reset() }
        if let _webView {
            usedWebViews.append(_webView)
            self._webView = nil
        }
        self.usedDelegates.append(navigationDelegateProxy)
        navigationDelegateProxy = DistributedNavigationDelegateTests.makeNavigationDelegateProxy()
    }
    
}

@available(macOS 12.0, *)
extension DistributedNavigationDelegateTestsBase {

    static func makeNavigationDelegateProxy() -> NavigationDelegateProxy {
        NavigationDelegateProxy(delegate: DistributedNavigationDelegate(logger: .default))
    }

    func makeWebView() -> WKWebView {
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
    }

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

        let customSchemeInteractionStateData = Data.sessionRestorationMagic + """
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
                    <string>\(TestNavigationSchemeHandler.scheme)://duckduckgo.com</string>
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

    func responder(at index: Int) -> NavigationResponderMock! {
        for (idx, responder) in navigationDelegate.responders.enumerated() where idx == index {
            return responder as? NavigationResponderMock
        }
        fatalError("responder at \(index) not present")
    }

    func navAct(_ idx: UInt64) -> NavAction {
        return responder(at: 0).navigationActionsCache.dict[idx]!
    }
    func resp(_ idx: Int) -> NavResponse {
        return responder(at: 0).navigationResponses[idx]
    }

    // MARK: FrameInfo mocking

    func main(_ current: URL = .empty, secOrigin: SecurityOrigin? = nil) -> FrameInfo {
        FrameInfo(frameIdentity: .mainFrameIdentity(for: webView), url: current, securityOrigin: secOrigin ?? current.securityOrigin)
    }

    func frame(_ handle: String, _ url: URL, secOrigin: SecurityOrigin? = nil) -> FrameInfo {
        FrameInfo(frameIdentity: FrameIdentity(handle: handle, webViewIdentity: .init(nonretainedObject: webView), isMainFrame: false), url: url, securityOrigin: secOrigin ?? url.securityOrigin)
    }
    func frame(_ handle: String, _ url: String, secOrigin: SecurityOrigin? = nil) -> FrameInfo {
        frame(handle, URL(string: url)!, secOrigin: secOrigin)
    }

    // Event sequence checking
    func assertHistory(ofResponderAt responderIdx: Int, equalsTo rhs: [TestsNavigationEvent], file: StaticString = #file, line: UInt = #line) {
        let lhs = responder(at: responderIdx).history
        for idx in 0..<max(lhs.count, rhs.count) {
            let event1 = lhs.indices.contains(idx) ? lhs[idx] : nil
            let event2 = rhs.indices.contains(idx) ? rhs[idx] : nil
            if event1 != event2 {
                printEncoded(responder: responderIdx)

                if case .navigationAction(let r1, _) = event1, case .navigationAction(let r2, _) = event2 {
                    XCTFail("#\(idx):" + NavAction.difference(between: r1, and: r2)!)
                    continue
                } else if case .navigationResponse(.navigation(let n1)) = event1, case .navigationResponse(.navigation(let n2)) = event2 {
                    XCTFail("#\(idx):" + Nav.difference(between: n1, and: n2)!)
                    continue
                } else if case .didFinish(let n1) = event1, case .didFinish(let n2) = event2 {
                    XCTFail("#\(idx):" + Nav.difference(between: n1, and: n2)!)
                    continue
                } else if case .didCommit(let n1) = event1, case .didCommit(let n2) = event2 {
                    XCTFail("#\(idx):" + Nav.difference(between: n1, and: n2)!)
                    continue
                } else if case .didFail(let nav1, let code1, isProvisional: let isProvisional1) = event1,
                          case .didFail(let nav2, let code2, isProvisional: let isProvisional2) = event2 {
                    XCTAssertEqual(code1, code2, "#\(idx): code")
                    XCTAssertEqual(isProvisional1, isProvisional2, "#\(idx): isProvisional")
                    XCTFail("#\(idx):" + Nav.difference(between: nav1, and: nav2)!)
                    continue
                } else if case .navigationResponse(.response(let resp1, let nav1)) = event1,
                          case .navigationResponse(.response(let resp2, let nav2)) = event2 {

                    if let diff = NavigationResponse.difference(between: resp1.response, and: resp2.response) {
                        XCTFail("#\(idx):" + diff)
                    }
                    if let nav1, let nav2, let diff = Nav.difference(between: nav1, and: nav2) {
                        XCTFail("#\(idx):" + diff)
                    } else {
                        XCTFail("#\(idx): \(nav1.debugDescription) not equal to \(nav2.debugDescription)")
                    }
                    continue
                }

                XCTFail("#\(idx):\n\(event1 != nil ? "\(event1!)" : "<nil>")\n not equal to" +
                        "\n\(event2 != nil ? "\(event2!)" : "<nil>")",
                        file: file, line: line)
            }
        }
    }

    func assertHistory(ofResponderAt responderIdx: Int, equalsToHistoryOfResponderAt responderIdx2: Int,
                       file: StaticString = #file,
                       line: UInt = #line) {
        assertHistory(ofResponderAt: responderIdx, equalsTo: responder(at: responderIdx2).history)
    }

    func encodedResponderHistory(at idx: Int = 0) -> String {
        responder(at: idx).history.encoded(with: urls, webView: webView, dataSource: data, history: history, responderNavigationResponses: responder(at: 0).navigationResponses)
    }

    func printEncoded(responder idx: Int = 0) {
        print("Responder #\(idx) history encoded:")
        print(encodedResponderHistory(at: idx))
    }

}
