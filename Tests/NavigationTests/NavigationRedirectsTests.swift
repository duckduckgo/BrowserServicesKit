//
//  NavigationRedirectsTests.swift
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

import Combine
import Common
import Swifter
import WebKit
import XCTest
@testable import Navigation

// swiftlint:disable file_length
// swiftlint:disable line_length
// swiftlint:disable function_body_length
// swiftlint:disable unused_closure_parameter
// swiftlint:disable type_body_length
// swiftlint:disable trailing_comma
// swiftlint:disable opening_brace
// swiftlint:disable force_try

@available(macOS 12.0, *)
class  NavigationRedirectsTests: DistributedNavigationDelegateTestsBase {

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
        responder(at: 0).onNavigationAction = { navigationAction, _ in .allow }

        let eDidSameDocumentNavigation = expectation(description: "#2")
        customCallbacksHandler.didSameDocumentNavigation = { _, type in
            if type == 3 { eDidSameDocumentNavigation.fulfill() }
        }

        webView.load(req(urls.local))
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .navigationActionReceived)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.sameDocumentClientRedirectData.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),

                .willStart(Nav(action: NavAction(req(urls.localHashed1, defaultHeaders + ["Referer": urls.local.separatedString]), .sameDocumentNavigation, from: history[1], src: main(urls.local)), .navigationActionReceived)),

                .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed))
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
        responder(at: 0).onNavigationAction = { navigationAction, _ in .allow }

        webView.load(req(urls.local3Hashed))
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local3Hashed), .other, src: main()),
            .willStart(Nav(action: navAct(1), .navigationActionReceived)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local3Hashed, data.clientRedirectData.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didReceiveRedirect(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local3.string]), .redirect(.client), from: history[1], redirects: [navAct(1)], src: main(urls.local3Hashed)),
                                Nav(action: navAct(1), .redirected(.client), resp: resp(0), .committed)),

                .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),

                .navigationAction(navAct(2)),
            .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .navigationActionReceived)),
            .didStart(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local3, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, resp: resp(1), .committed))
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
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .navigationActionReceived)),
            .didStart(Nav(action: navAct(1), .started)),

                .navigationAction(req(urls.local2, defaultHeaders + ["Upgrade-Insecure-Requests": "1", "Accept-Encoding": "gzip, deflate", "Accept-Language": "en-XX,en;q=0.9"]), .redirect(.server), redirects: [navAct(1)], src: main()),
            .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .redirected(.server))),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),

                .navigationAction(req(urls.local3, defaultHeaders + ["Accept-Encoding": "gzip, deflate", "Accept-Language": "en-GB,en;q=0.9", "Upgrade-Insecure-Requests": "1"]), .redirect(.server), redirects: [navAct(1), navAct(2)], src: main()),
            .willStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .redirected(.server))),
            .didReceiveRedirect(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .started)),

                .response(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .responseReceived, resp: .resp(urls.local3, status: 200, data.html.count))),
            .didCommit(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .finished, resp: resp(0), .committed))
        ])
    }

    func testRefreshHeaderRedirectWithDelay() throws {
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
        autoreleasepool {
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .navigationActionReceived)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, mime: "text/plain", headers: ["Refresh": "1; url=/2", "Server": "Swifter Unspecified"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),

                .didReceiveRedirect(NavAction(req(urls.local2, defaultHeaders + ["Referer": urls.local.separatedString]), .redirect(.client(delay: 1.0)), from: history[1], redirects: [navAct(1)], src: main(urls.local)),
                                    Nav(action: navAct(1), .redirected(.client(delay: 1)), resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),

                .navigationAction(navAct(2)),
            .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .navigationActionReceived)),
            .didStart(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local2, data.html.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, resp: resp(1), .committed))
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
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .navigationActionReceived)),
            .didStart(Nav(action: navAct(1), .started)),

                .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Language": "en-XX,en;q=0.9", "Upgrade-Insecure-Requests": "1", "Accept-Encoding": "gzip, deflate"]), .redirect(.server), redirects: [navAct(1)], src: main()),
            .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .redirected(.server))),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),

                .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local2, data.metaRedirect.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: resp(0), .committed)),
            .didReceiveRedirect(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local2.string]), .redirect(.client), from: history[2], redirects: [navAct(1), navAct(2)], src: main(urls.local2)),
                                Nav(action: navAct(2), redirects: [navAct(1)], .redirected(.client), resp: resp(0), .committed)),

                .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, resp: resp(0), .committed)),

                .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local2.string]), .redirect(.client), from: history[2], redirects: [navAct(1), navAct(2)], src: main(urls.local2)),
            .willStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .navigationActionReceived)),
            .didStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .started)),

                .navigationAction(req(urls.local4, defaultHeaders + ["Accept-Encoding": "gzip, deflate", "Upgrade-Insecure-Requests": "1", "Accept-Language": "en-GB,en;q=0.9", "Referer": urls.local2.string]), .redirect(.server), from: history[2], redirects: [navAct(1), navAct(2), navAct(3)], src: main(urls.local2)),
            .willStart(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .redirected(.server))),
            .didReceiveRedirect(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .started)),

                .response(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .responseReceived, resp: .resp(urls.local4, data.html.count))),
            .didCommit(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .finished, resp: resp(1), .committed))
        ])
    }

    func testClientRedirectAfterMetaRedirect() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish = expectation(description: "onDidFinish")
        var counter = 0
        responder(at: 0).onDidFinish = { _ in
            counter += 1
            guard counter == 4 else { return }
            eDidFinish.fulfill()
        }

        var clientRedirectMade = false
        server.middleware = [{ [urls, data] request in
            switch request.path {
            case "/":
                return .ok(.data(data.metaRedirect))
            case urls.local3.path:
                defer { clientRedirectMade = true }
                return .ok(.data(clientRedirectMade ? data.clientRedirectData2 : data.clientRedirectData))
            default:
                return .ok(.data(data.html))
            }
        }]
        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .navigationActionReceived)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.metaRedirect.count))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didReceiveRedirect(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .redirect(.client), from: history[1], redirects: [navAct(1)], src: main(urls.local)),
                                Nav(action: navAct(1), .redirected(.client), resp: resp(0), .committed)),

                .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),

                .navigationAction(navAct(2)),
            .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .navigationActionReceived)),
            .didStart(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local3, data.clientRedirectData.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: resp(1), .committed)),
            .didReceiveRedirect(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local3.string]), .redirect(.client), from: history[1], redirects: [navAct(1), navAct(2)], src: main(urls.local3)),
                                Nav(action: navAct(2), redirects: [navAct(1)], .redirected(.client), resp: resp(1), .committed)),

                .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, resp: resp(1), .committed)),

                .navigationAction(navAct(3)),
            .willStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .navigationActionReceived)),
            .didStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .started)),
            .response(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .responseReceived, resp: resp(1))),
            .didCommit(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .responseReceived, resp: resp(1), .committed)),
            .didReceiveRedirect(NavAction(req(urls.local2, defaultHeaders + ["Referer": urls.local3.string]), .redirect(.client), from: history[1], redirects: [navAct(1), navAct(2), navAct(3)], src: main(urls.local3)),
                                Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .redirected(.client), resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .finished, resp: resp(1), .committed)),

                .navigationAction(navAct(4)),
            .willStart(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .navigationActionReceived)),
            .didStart(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .started)),
            .response(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .responseReceived, resp: .resp(urls.local2, data.html.count))),
            .didCommit(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .responseReceived, resp: resp(3), .committed)),
            .didFinish(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .finished, resp: resp(3), .committed))
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
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .navigationActionReceived)),
            .didStart(Nav(action: navAct(1), .started)),

                .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Language": "en-GB,en;q=0.9", "Upgrade-Insecure-Requests": "1", "Accept-Encoding": "gzip, deflate"]), .redirect(.server), redirects: [navAct(1)], src: main()),
            .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .redirected(.server))),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),

                .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local2, data.metaRedirect.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: resp(0), .committed)),
            .didReceiveRedirect(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local2.string]), .redirect(.client), from: history[2], redirects: [navAct(1), navAct(2)], src: main(urls.local2)), Nav(action: navAct(2), redirects: [navAct(1)], .redirected(.client), resp: resp(0), .committed)),

                .navigationAction(navAct(3)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, resp: resp(0), .committed)),

                .willStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .navigationActionReceived)),
            .didStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .started)),

                .navigationAction(req(urls.local4, defaultHeaders + ["Accept-Encoding": "gzip, deflate", "Upgrade-Insecure-Requests": "1", "Accept-Language": "en-GB,en;q=0.9", "Referer": urls.local2.string]), .redirect(.server), from: history[2], redirects: [navAct(1), navAct(2), navAct(3)], src: main(urls.local2)),
            .willStart(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .redirected(.server))),
            .didReceiveRedirect(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .started)),

                .response(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .responseReceived, resp: .resp(urls.local4, data.html.count))),
            .didCommit(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .finished, resp: resp(1), .committed))
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
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .navigationActionReceived)),
            .didStart(Nav(action: navAct(1), .started)),

                .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Language": "en-GB,en;q=0.9", "Upgrade-Insecure-Requests": "1", "Accept-Encoding": "gzip, deflate"]), .redirect(.server), redirects: [navAct(1)], src: main()),
            .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .redirected(.server))),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),

                .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local2, data.metaRedirect.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: resp(0), .committed)),
            .didReceiveRedirect(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local2.string]), .redirect(.client), from: history[2], redirects: [navAct(1), navAct(2)], src: main(urls.local2)),
                                Nav(action: navAct(2), redirects: [navAct(1)], .redirected(.client), resp: resp(0), .committed)),

                .navigationAction(navAct(3)),
            .willStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .navigationActionReceived)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, resp: resp(0), .committed)),

                .didStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .started)),

                .navigationAction(req(urls.local4, defaultHeaders + ["Accept-Encoding": "gzip, deflate", "Upgrade-Insecure-Requests": "1", "Accept-Language": "en-GB,en;q=0.9", "Referer": urls.local2.string]), .redirect(.server), from: history[2], redirects: [navAct(1), navAct(2), navAct(3)], src: main(urls.local2)),
            .willStart(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .redirected(.server))),
            .didReceiveRedirect(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .started)),

                .response(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .responseReceived, resp: .resp(urls.local4, data.html.count))),
            .didCommit(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .finished, resp: resp(1), .committed))
        ])
    }

    func testClientRedirect() throws {
        navigationDelegateProxy.finishEventsDispatchTime = .beforeWillStartNavigationAction
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
        autoreleasepool {
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .navigationActionReceived)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.clientRedirectData.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),

                .didReceiveRedirect(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .redirect(.client), from: history[1], redirects: [navAct(1)], src: main(urls.local)),
                                    Nav(action: navAct(1), .redirected(.client), resp: resp(0), .committed)),
            .navigationAction(navAct(2)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),


                .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .navigationActionReceived)),
            .didStart(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local3, data.clientRedirectData.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: resp(1), .committed)),
            .didReceiveRedirect(NavAction(req(urls.local2, defaultHeaders + ["Referer": urls.local3.string]), .redirect(.client), from: history[1], redirects: [navAct(1), navAct(2)], src: main(urls.local3)),
                                Nav(action: navAct(2), redirects: [navAct(1)], .redirected(.client), resp: resp(1), .committed)),
            .navigationAction(navAct(3)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, resp: resp(1), .committed)),

                .willStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .navigationActionReceived)),
            .didStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .started)),
            .response(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .responseReceived, resp: .resp(urls.local2, data.html.count))),
            .didCommit(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .responseReceived, resp: resp(2), .committed)),
            .didFinish(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .finished, resp: resp(2), .committed))
        ])
    }

    func testClientRedirectWithDelay() throws {
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
            .willStart(Nav(action: navAct(1), .navigationActionReceived)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.metaRedirect.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didReceiveRedirect(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .redirect(.client(delay: 1.0)), from: history[1], redirects: [navAct(1)], src: main(urls.local)),
                                Nav(action: navAct(1), .redirected(.client(delay: 1)), resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),

                .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .redirect(.client(delay: 1.0)), from: history[1], redirects: [navAct(1)], src: main(urls.local)),
            .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .navigationActionReceived)),
            .didStart(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local3, data.html.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, resp: resp(1), .committed))
        ])
    }

    func testClientRedirectWithoutWillPerformClientRedirect() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        navigationDelegateProxy.enableWillPerformClientRedirect = false

        let eDidFinish1 = expectation(description: "onDidFinish")
        let eDidFinish2 = expectation(description: "onDidFinish 2")
        var eDidFinish = eDidFinish1
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
            eDidFinish = eDidFinish2
        }

        server.middleware = [{ [data] request in
            guard request.path == "/" else { return nil }
            return .ok(.html(data.clientRedirectData.string()!))
        }, { [data] request in
            return .ok(.data(data.html))
        }]
        try server.start(8084)
        webView.load(req(urls.local))
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .navigationActionReceived)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.clientRedirectData.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),

                .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: main(urls.local)),
            .willStart(Nav(action: navAct(2), .navigationActionReceived)),
            .didStart(Nav(action: navAct(2), .started)),
            .response(Nav(action: navAct(2), .responseReceived, resp: .resp(urls.local3, data.html.count))),
            .didCommit(Nav(action: navAct(2), .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(2), .finished, resp: resp(1), .committed))
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
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .navigationActionReceived)),
            .didStart(Nav(action: navAct(1), .started)),

                .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Encoding": "gzip, deflate", "Accept-Language": "en-XX,en;q=0.9", "Upgrade-Insecure-Requests": "1"]), .redirect(.server), redirects: [navAct(1)], src: main()),
            .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .redirected(.server))),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local2, data.metaRedirect.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: resp(0), .committed)),
            .didReceiveRedirect(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local2.string]), .redirect(.client), from: history[2], redirects: [navAct(1), navAct(2)], src: main(urls.local2)), Nav(action: navAct(2), redirects: [navAct(1)], .redirected(.client), resp: resp(0), .committed)),

                .navigationAction(navAct(3)),
            .willStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .navigationActionReceived)),
            .didStart(Nav(action: navAct(3), redirects: [navAct(1), navAct(2)], .started)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)], .finished, resp: resp(0), .committed)),

                .navigationAction(req(urls.local4, defaultHeaders + ["Upgrade-Insecure-Requests": "1", "Accept-Language": "en-XX,en;q=0.9", "Accept-Encoding": "gzip, deflate", "Referer": urls.local2.string]), .redirect(.server), from: history[2], redirects: [navAct(1), navAct(2), navAct(3)], src: main(urls.local2)),
            .willStart(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .redirected(.server))),
            .didReceiveRedirect(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .started)),
            .response(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .responseReceived, resp: .resp(urls.local4, data.html.count))),
            .didCommit(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(4), redirects: [navAct(1), navAct(2), navAct(3)], .finished, resp: resp(1), .committed))
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
        waitForExpectations(timeout: 5)

        var expected: [TestsNavigationEvent] =  [

            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .navigationActionReceived)),
            .didStart(Nav(action: navAct(1), .started)),
            .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Language": "en-GB,en;q=0.9", "Upgrade-Insecure-Requests": "1", "Accept-Encoding": "gzip, deflate"]), .redirect(.server), redirects: [navAct(1)], src: main()),
            .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .redirected(.server))),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            // .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1), navAct(2)...], .started)),

                .response(Nav(action: navAct(2), redirects: [navAct(1)] + .init(repeating: navAct(2), count: 9), .responseReceived, resp: .resp(urls.local2, data.html.count))),
            .didCommit(Nav(action: navAct(2), redirects: [navAct(1)] + .init(repeating: navAct(2), count: 9), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(2), redirects: [navAct(1)] + .init(repeating: navAct(2), count: 9), .finished, resp: resp(0), .committed))

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
        responder(at: 0).onDidFail = { _, _, _ in
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
        waitForExpectations(timeout: 5)

        var expected: [TestsNavigationEvent] =  [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .navigationActionReceived)),
            .didStart(Nav(action: navAct(1), .started)),

                .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Language": "en-GB,en;q=0.9", "Upgrade-Insecure-Requests": "1", "Accept-Encoding": "gzip, deflate"]), .redirect(.server), redirects: [navAct(1)], src: main()),
            .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .redirected(.server))),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            // ...didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1), navAct(2)...], .started)

                .didFail(Nav(action: navAct(2), redirects: [navAct(1)] + .init(repeating: navAct(2), count: 19), .failed(WKError(NSURLErrorHTTPTooManyRedirects))), NSURLErrorHTTPTooManyRedirects, isProvisioned: false)
        ]
        while expected[expected.count - 2].redirectEvent!.redirects.count < 20 {
            expected.insert(.didReceiveRedirect(Nav(action: navAct(2),
                                                    redirects: [navAct(1)]
                                                    + .init(repeating: navAct(2), count: expected[expected.count - 2].redirectEvent!.redirects.count),
                                                    .started)), at: expected.count - 1)
        }

        assertHistory(ofResponderAt: 0, equalsTo: expected)
    }

    func testDeveloperRedirectToSimulatedRequest() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        responder(at: 0).onNavigationAction = { [urls, data] action, _ in
            if action.url.matches(urls.local) {
                return .redirect(action.mainFrameTarget!) { webView in
                    webView.loadSimulatedRequest(req(urls.https), responseHTML: String(data: data.html, encoding: .utf8)!, withExpectedNavigationType: .custom(.init(rawValue: "redir")))
                }
            } else {
                XCTAssertEqual(action.navigationType, .custom(.init(rawValue: "redir")))
                return .allow
            }
        }

        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]

        // regular navigation from an empty state
        try server.start(8084)
        autoreleasepool {
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        XCTAssertFalse(navAct(1).navigationAction.isTargetingNewWindow)
        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(NavAction(req(urls.local), .other, src: main())),
            .didFail(Nav(action: navAct(1), .failed(WKError(NSURLErrorCancelled))), NSURLErrorCancelled, isProvisioned: false),

                .navigationAction(NavAction(req(urls.https), .custom(.init(rawValue: "redir")), src: main())),
            .willStart(Nav(action: navAct(2), .navigationActionReceived)),
            .didStart(Nav(action: navAct(2), .started)),
            .didCommit(Nav(action: navAct(2), .started, .committed)),
            .didFinish(Nav(action: navAct(2), .finished, .committed))
        ])
    }

    func testDeveloperRedirectToAboutBlank() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        responder(at: 0).onNavigationAction = { [urls] action, _ in
            if action.url.matches(urls.local) {
                return .redirect(action.mainFrameTarget!) { webView in
                    webView.load(req(urls.aboutBlank))
                }
            } else {
                XCTAssertEqual(action.navigationType, .custom(.init(rawValue: "redir")))
                return .allow
            }
        }

        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]

        // regular navigation from an empty state
        try server.start(8084)
        autoreleasepool {
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 50)

        XCTAssertFalse(navAct(1).navigationAction.isTargetingNewWindow)
        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(NavAction(req(urls.local), .other, src: main())),
            .didFail(Nav(action: navAct(1), .failed(WKError(NSURLErrorCancelled))), NSURLErrorCancelled, isProvisioned: false),

                .willStart(Nav(action: NavAction(req(urls.aboutBlank), .redirect(.developer), src: main()), .navigationActionReceived)),
            .didStart(Nav(action: navAct(2), .started)),
            .didCommit(Nav(action: navAct(2), .started, .committed)),
            .didFinish(Nav(action: navAct(2), .finished, .committed))
        ])
    }

    func testWhenRedirectIsInterruptedThenDidFailNonProvisionalIsCalled() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [urls, data] request in
            guard request.path == "/" else { return nil }

            return .raw(301, "Moved", ["Location": urls.local2.path]) { writer in
                try! writer.write(data.empty)
            }
        }, { [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        responder(at: 0).onNavigationAction = { [urls] action, _ in
            if action.url.matches(urls.local2) {
                return .cancel
            }
            return .allow
        }
        let eOnDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { _, _, _ in
            eOnDidFail.fulfill()
        }

        autoreleasepool {
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .navigationActionReceived)),
            .didStart(Nav(action: navAct(1), .started)),

                .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Language": "en-XX,en;q=0.9", "Accept-Encoding": "gzip, deflate", "Upgrade-Insecure-Requests": "1"]), .redirect(.server), redirects: [navAct(1)], src: main()),

                .didFail(Nav(action: navAct(2), redirects: [navAct(1)], .failed(WKError(.frameLoadInterruptedByPolicyChange))), WKError.Code.frameLoadInterruptedByPolicyChange.rawValue, isProvisioned: false)
        ])
    }

    // TODO: Expected navigation type for multiple .redirect navigations
    // TODO: test server redirect to same document
    // TODO: cancel client redirect

    // TODO: func testClientRedirectWithFakeBackAction() throws {
    //        navigationDelegateProxy.finishEventsDispatchTime = .afterWillStartNavigationAction
    //        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
    //
    //        server.middleware = [{ [data] request in
    //            guard request.path == "/" else { return nil }
    //            return .ok(.html(data.clientRedirectData.string()!))
    //        }, { [urls, data] request in
    //            guard request.path == urls.local3.path else { return nil }
    //            return .ok(.html(data.clientRedirectData2.string()!))
    //        }, { [data] request in
    //            return .ok(.data(data.html))
    //        }]
    //        try server.start(8084)
    //
    //        let eDidFinish1 = expectation(description: "onDidFinish 1")
    //        responder(at: 0).onDidFinish = { _ in
    //            eDidFinish1.fulfill()
    //        }
    //
    //        webView.load(req(urls.local4))
    //        waitForExpectations(timeout: 5)
    //        responder(at: 0).clear()
    //
    //        var counter = 0
    //        let eDidFinish = expectation(description: "onDidFinish 2")
    //        responder(at: 0).onDidFinish = { _ in
    //            counter += 1
    //            guard counter == 2 else { return }
    //            eDidFinish.fulfill()
    //        }
    //
    //        responder(at: 0).onNavigationAction = { [urls] action, _ in
    //            if action.url.path == urls.local3.path {
    //                return .cancel(with: .redirect(req(urls.local4)))
    //            }
    //            return .allow
    //        }
    //        responder(at: 0).onWillCancel = { [webView, urls] _, redir in
    //            guard case .redirect(let newRequest) = redir, newRequest == req(urls.local4) else {
    //                XCTFail("unexpected redir action")
    //                return
    //            }
    //
    //            webView.goBack()
    //            webView.load(newRequest)
    //        }
    //
    //        webView.load(req(urls.local))
    //        waitForExpectations(timeout: 5)
    //
    //        assertHistory(ofResponderAt: 0, equalsTo: [
    //            .navigationAction(req(urls.local), .other, from: history[1], src: main(urls.local4)),
    //            // willStart(navAct(2)),
    //            .didStart(Nav(action: navAct(2), .started)),
    //            .response(Nav(action: navAct(2), .resp(urls.local, data.clientRedirectData.count, headers: .default + ["Content-Type": "text/html"]))),
    //            .didCommit(Nav(action: navAct(2), .resp(urls.local, data.clientRedirectData.count, headers: .default + ["Content-Type": "text/html"]), .committed)),
    //
    //            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .redirect(.client), from: history[2], redirects: [navAct(2)], src: main(urls.local)),
    //            .willCancel(navAct(3), .redir(urls.local4)),
    //            .didCancel(navAct(3), .redir(urls.local4)),
    //            .didFinish(Nav(action: navAct(2), .finished, .committed)),
    //
    //            .navigationAction(req(urls.local4, defaultHeaders + ["Upgrade-Insecure-Requests": "1"]), .backForw(-1), from: history[2], src: main(urls.local)),
    //            // willStart(navAct(4)),
    //
    //            .navigationAction(req(urls.local4), .other, from: history[2], src: main(urls.local)),
    //            // willStart(navAct(5)),
    //            .didStart(Nav(action: navAct(5), .started)),
    //            .response(Nav(action: navAct(5), .resp(urls.local4, data.html.count))),
    //            .didCommit(Nav(action: navAct(5), .resp(urls.local4, data.html.count), .committed)),
    //            .didFinish(Nav(action: navAct(5), .finished, .committed))
    //        ])
    //    }
}
