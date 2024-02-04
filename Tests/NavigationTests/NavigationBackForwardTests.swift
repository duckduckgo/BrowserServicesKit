//
//  NavigationBackForwardTests.swift
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

#if os(macOS)

import Combine
import Common
import Swifter
import WebKit
import XCTest
@testable import Navigation

// swiftlint:disable unused_closure_parameter
// swiftlint:disable trailing_comma
// swiftlint:disable opening_brace

@available(macOS 12.0, iOS 15.0, *)
class NavigationBackForwardTests: DistributedNavigationDelegateTestsBase {

    func testGoBackForward() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        var eDidFinish = expectation(description: "onDidFinish 1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        eDidFinish = expectation(description: "onDidFinish 2")
        withWebView { webView in
            _=webView.load(req(urls.local1))
        }
        waitForExpectations(timeout: 5)

        eDidFinish = expectation(description: "onDidFinish back")
        withWebView { webView in
            _=webView.goBack()
        }
        waitForExpectations(timeout: 5)

        eDidFinish = expectation(description: "onDidFinish forw")
        withWebView { webView in
            _=webView.goForward()
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            // #1
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),

            // #2
            .navigationAction(req(urls.local1), .other, from: history[1], src: main(urls.local)),
            .willStart(Nav(action: navAct(2), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(2), .started)),
            .response(Nav(action: navAct(2), .responseReceived, resp: .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(2), .finished, resp: resp(1), .committed)),

            // #2 -> #1 back
            .navigationAction(req(urls.local, defaultHeaders.allowingExtraKeys), .backForw(-1), from: history[2], src: main(urls.local1)),
            .willStart(Nav(action: navAct(3), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(3), .started)),
            .didCommit(Nav(action: navAct(3), .started, .committed)),
            .didFinish(Nav(action: navAct(3), .finished, .committed)),

            // #1 -> #2 forward
            .navigationAction(req(urls.local1, defaultHeaders.allowingExtraKeys), .backForw(1), from: history[1], src: main(urls.local)),
            .willStart(Nav(action: navAct(4), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(4), .started)),
            .didCommit(Nav(action: navAct(4), .started, .committed)),
            .didFinish(Nav(action: navAct(4), .finished, .committed)),
        ])
    }

    func testJSGoBackForward() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        var eDidFinish = expectation(description: "onDidFinish 1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        eDidFinish = expectation(description: "onDidFinish 2")
        withWebView { webView in
            _=webView.load(req(urls.local1))
        }
        waitForExpectations(timeout: 5)

        eDidFinish = expectation(description: "onDidFinish back")
        withWebView { webView in
            webView.evaluateJavaScript("history.back()")
        }
        waitForExpectations(timeout: 5)

        eDidFinish = expectation(description: "onDidFinish forw")
        withWebView { webView in
            webView.evaluateJavaScript("history.forward()")
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            // #1
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),

            // #2
            .navigationAction(req(urls.local1), .other, from: history[1], src: main(urls.local)),
            .willStart(Nav(action: navAct(2), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(2), .started)),
            .response(Nav(action: navAct(2), .responseReceived, resp: .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(2), .finished, resp: resp(1), .committed)),

            // #2 -> #1 back
            .navigationAction(req(urls.local, defaultHeaders.allowingExtraKeys), .backForw(-1), from: history[2], src: main(urls.local1)),
            .willStart(Nav(action: navAct(3), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(3), .started)),
            .didCommit(Nav(action: navAct(3), .started, .committed)),
            .didFinish(Nav(action: navAct(3), .finished, .committed)),

            // #1 -> #2 forward
            .navigationAction(req(urls.local1, defaultHeaders.allowingExtraKeys), .backForw(1), from: history[1], src: main(urls.local)),
            .willStart(Nav(action: navAct(4), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(4), .started)),
            .didCommit(Nav(action: navAct(4), .started, .committed)),
            .didFinish(Nav(action: navAct(4), .finished, .committed)),
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

            withWebView { webView in
                _=webView.load(req(url))
            }
            waitForExpectations(timeout: 5)
        }

        responder(at: 0).clear()

        eDidFinish = expectation(description: "onDidFinish back")
        withWebView { webView in
            _=webView.go(to: webView.backForwardList.item(at: -3)!)
        }
        waitForExpectations(timeout: 5)

        eDidFinish = expectation(description: "onDidFinish forw")
        withWebView { webView in
            _=webView.go(to: webView.backForwardList.item(at: 3)!)
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local1, cachePolicy: .returnCacheDataElseLoad), .backForw(-3), from: history[5], src: main(urls.local4)),
            .willStart(Nav(action: navAct(6), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(6), .started)),
            .response(Nav(action: navAct(6), .responseReceived, resp: .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(6), .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(6), .finished, resp: resp(1), .committed)),

            .navigationAction(req(urls.local4, defaultHeaders.allowingExtraKeys), .backForw(3), from: history[2], src: main(urls.local1)),
            .willStart(Nav(action: navAct(7), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(7), .started)),
            .didCommit(Nav(action: navAct(7), .started, .committed)),
            .didFinish(Nav(action: navAct(7), .finished, .committed)),
        ])
    }

    func testGoBackInFrame() throws {
        let didFinishLoadingFrameHandler = CustomCallbacksHandler()
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })), .weak(didFinishLoadingFrameHandler))

        server.middleware = [{ [data] request in
            guard request.path == "/" else { return nil }
            return .ok(.html(data.htmlWithIframe3.string()!))
        }, { [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        let eDidFinish = expectation(description: "onDidFinish 1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        var frameID: UInt64!
        responder(at: 0).onNavigationAction = { [urls] navAction, _ in
            if navAction.url.path == urls.local3.path {
#if _FRAME_HANDLE_ENABLED
                frameID = navAction.targetFrame?.handle.frameID
                XCTAssertNotEqual(frameID, WKFrameInfo.defaultMainFrameHandle)
#endif
            }
            return .next
        }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        var eDidFinishLoadingFrame = expectation(description: "didFinishLoadingFrame 1")
        didFinishLoadingFrameHandler.didFinishLoadingFrame = { request, frame in
            eDidFinishLoadingFrame.fulfill()
        }
        didFinishLoadingFrameHandler.didFailProvisionalLoadInFrame = { _, _, error in XCTFail("Unexpected failure \(error)") }

        withWebView { webView in
            webView.evaluateJavaScript("window.frames[0].location.href = '\(urls.local1.string)'")
        }
        waitForExpectations(timeout: 5)

        eDidFinishLoadingFrame = expectation(description: "didFinishLoadingFrame back")
        withWebView { webView in
            _=webView.goBack()
        }
        waitForExpectations(timeout: 5)

        eDidFinishLoadingFrame = expectation(description: "didFinishLoadingFrame forw")
        withWebView { webView in
            _=webView.goForward()
        }
        waitForExpectations(timeout: 5)

        XCTAssertFalse(navAct(2).navigationAction.isTargetingNewWindow)
        XCTAssertFalse(navAct(3).navigationAction.isTargetingNewWindow)
        XCTAssertFalse(navAct(4).navigationAction.isTargetingNewWindow)
        XCTAssertFalse(navAct(5).navigationAction.isTargetingNewWindow)
        assertHistory(ofResponderAt: 0, equalsTo: [
            // #1 main nav
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.htmlWithIframe3.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            // #2 frame nav
            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(WKFrameInfo.defaultMainFrameHandle, urls.local), targ: frame(frameID, .empty, secOrigin: urls.local.securityOrigin)),
            .response(.resp(urls.local3, data.html.count, headers: .default + ["Content-Type": "text/html"], .nonMain), Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),

            // #3 js frame nav
            .navigationAction(req(urls.local1, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(WKFrameInfo.defaultMainFrameHandle, urls.local), targ: frame(frameID, urls.local3)),
            .response(.resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"], .nonMain), nil),

            // #3 -> #1 goBack in frame
            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString], cachePolicy: .returnCacheDataElseLoad), .backForw(-1), from: history[3], src: frame(frameID, urls.local1)),
            .response(resp(1), nil),
            // #1 -> #3 goForward in frame
            .navigationAction(req(urls.local1, defaultHeaders + ["Referer": urls.local.separatedString], cachePolicy: .returnCacheDataElseLoad), .backForw(1), from: history[1], src: frame(frameID, urls.local3)),
            .response(.resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"], .nonMain), nil),
        ])
    }

    func testGoBackInFrameAfterCacheClearing() throws {
        let didFinishLoadingFrameHandler = CustomCallbacksHandler()
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })), .weak(didFinishLoadingFrameHandler))

        server.middleware = [{ [data] request in
            guard request.path == "/" else { return nil }
            return .ok(.html(data.htmlWithIframe3.string()!))
        }, { [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        let eDidFinish = expectation(description: "onDidFinish 1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        var frameID: UInt64!
        responder(at: 0).onNavigationAction = { [urls] navAction, _ in
#if _FRAME_HANDLE_ENABLED
            if navAction.url.path == urls.local3.path {
                frameID = navAction.targetFrame?.handle.frameID
                XCTAssertNotEqual(frameID, WKFrameInfo.defaultMainFrameHandle)
            }
#endif
            return .next
        }

        withWebView { webView in
            webView.interactionState = data.interactionStateData
        }
        waitForExpectations(timeout: 5)

        var eDidFinishLoadingFrame = expectation(description: "didFinishLoadingFrame 1")
        didFinishLoadingFrameHandler.didFinishLoadingFrame = { request, frame in
            eDidFinishLoadingFrame.fulfill()
        }
        didFinishLoadingFrameHandler.didFailProvisionalLoadInFrame = { _, _, error in XCTFail("Unexpected failure \(error)") }

        withWebView { webView in
            webView.evaluateJavaScript("window.frames[0].location.href = '\(urls.local1.string)'")
        }
        waitForExpectations(timeout: 5)

        let expectClearCache = expectation(description: "cache cleared")
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: Date(timeIntervalSince1970: 0)) {
            expectClearCache.fulfill()
        }
        waitForExpectations(timeout: 5)

        eDidFinishLoadingFrame = expectation(description: "didFinishLoadingFrame back")
        withWebView { webView in
            _=webView.goBack()
        }
        waitForExpectations(timeout: 5)

        let expectClearCache2 = expectation(description: "cache cleared 2")
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: Date(timeIntervalSince1970: 0)) {
            expectClearCache2.fulfill()
        }
        waitForExpectations(timeout: 5)

        eDidFinishLoadingFrame = expectation(description: "didFinishLoadingFrame forw")
        withWebView { webView in
            _=webView.goForward()
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            // #1 main nav
            .navigationAction(req(urls.local, cachePolicy: .returnCacheDataElseLoad), .restore, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.htmlWithIframe3.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            // #2 frame nav
            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(WKFrameInfo.defaultMainFrameHandle, urls.local), targ: frame(frameID, .empty, secOrigin: urls.local.securityOrigin)),
            .response(.resp(urls.local3, data.html.count, headers: .default + ["Content-Type": "text/html"], .nonMain), Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),

            // #3 js frame nav
            .navigationAction(req(urls.local1, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(WKFrameInfo.defaultMainFrameHandle, urls.local), targ: frame(frameID, urls.local3)),
            .response(.resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"], .nonMain), nil),

            // #3 -> #1 goBack in frame
            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString], cachePolicy: .returnCacheDataElseLoad), .backForw(-1), from: history[3], src: frame(frameID, urls.local1)),
            .response(resp(1), nil),

            // #1 -> #3 goForward in frame
            .navigationAction(req(urls.local1, defaultHeaders + ["Referer": urls.local.separatedString], cachePolicy: .returnCacheDataElseLoad), .backForw(1), from: history[1], src: frame(frameID, urls.local3)),
            .response(resp(2), nil)
        ])
    }

    func testGoBackWithSameDocumentNavigation() throws {
        let customCallbacksHandler = CustomCallbacksHandler()
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })), .weak(customCallbacksHandler))

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        var eDidFinish = expectation(description: "#1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        responder(at: 0).onNavigationAction = { navigationAction, _ in .allow }

        // #1 load URL
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        // #2 load URL#namedlink
        eDidFinish = expectation(description: "#2")
        customCallbacksHandler.didSameDocumentNavigation = { _, type in
            if type == .sessionStatePop { eDidFinish.fulfill() }
        }
        withWebView { webView in
            _=webView.load(req(urls.localHashed1))
        }
        waitForExpectations(timeout: 5)

        // #3 load URL#namedlink2
        eDidFinish = expectation(description: "#3")
        withWebView { webView in
            webView.evaluateJavaScript("window.location.href = '\(urls.localHashed2.string)'")
        }
        waitForExpectations(timeout: 5)

        // #4 load URL#namedlink
        eDidFinish = expectation(description: "#4")
        withWebView { webView in
            webView.evaluateJavaScript("window.location.href = '\(urls.localHashed1.string)'")
        }
        waitForExpectations(timeout: 5)

        // #4.1 go back to URL#namedlink2
        eDidFinish = expectation(description: "#4.1")
        withWebView { webView in
            _=webView.goBack()
        }
        waitForExpectations(timeout: 5)
        // #4.2
        eDidFinish = expectation(description: "#4.2")
        withWebView { webView in
            _=webView.goBack()
        }
        waitForExpectations(timeout: 5)
        // #4.3
        eDidFinish = expectation(description: "#4.3")
        withWebView { webView in
            _=webView.goForward()
        }
        waitForExpectations(timeout: 5)
        // #4.4
        eDidFinish = expectation(description: "#4.4")
        withWebView { webView in
            _=webView.goForward()
        }
        waitForExpectations(timeout: 5)

        // #5 load URL#
        eDidFinish = expectation(description: "#5")
        withWebView { webView in
            webView.evaluateJavaScript("window.location.href = '\(urls.localHashed.string)'")
        }
        waitForExpectations(timeout: 5)

        // #6 load URL
        eDidFinish = expectation(description: "#6")
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        // #7 go back to URL#
        // !! here‘s the WebKit bug: no forward item will be present here
        eDidFinish = expectation(description: "#7")
        withWebView { webView in
            _=webView.goBack()
        }
        waitForExpectations(timeout: 5)

        // #8 go back to URL#namedlink
        eDidFinish = expectation(description: "#8")
        withWebView { webView in
            _=webView.goBack()
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            // #1 load URL
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),

            // #2 load URL#namedlink
            .willStart(Nav(action: NavAction(req(urls.localHashed1), .sameDocumentNavigation, from: history[1], src: main(urls.local)), .approved, isCurrent: false)),
            // #3 load URL#namedlink2
            .willStart(Nav(action: NavAction(req(urls.localHashed2, defaultHeaders + ["Referer": urls.local.separatedString]), .sameDocumentNavigation, from: history[2], src: main(urls.localHashed1)), .approved, isCurrent: false)),
            // #3.1 load URL#namedlink
            .willStart(Nav(action: NavAction(req(urls.localHashed1, defaultHeaders + ["Referer": urls.local.separatedString]), .sameDocumentNavigation, from: history[3], src: main(urls.localHashed2)), .approved, isCurrent: false)),

            // goBack/goForward ignored for same doc decidePolicyForNavigationAction not called

            // #5 load URL#
            .willStart(Nav(action: NavAction(req(urls.localHashed, defaultHeaders + ["Referer": urls.local.separatedString]), .sameDocumentNavigation, from: history[4], src: main(urls.localHashed1)), .approved, isCurrent: false)),

            // #6 load URL
            .navigationAction(req(urls.local), .other, from: history[5], src: main(urls.localHashed)),
            .willStart(Nav(action: navAct(6), .approved, isCurrent: false)),
            .didStart( Nav(action: navAct(6), .started)),
            .response(Nav(action: navAct(6), .responseReceived, resp: resp(0))),
            .didCommit(Nav(action: navAct(6), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(6), .finished, resp: resp(0), .committed)),

            // history items replaced due to WebKit bug
            // #7 go back to URL#
            .willStart(Nav(action: NavAction(req(urls.localHashed, defaultHeaders.allowingExtraKeys), .backForw(-1), from: history[6], src: main(urls.local)), .approved, isCurrent: false)),
            // #8 go back to URL#namedlink
            .willStart(Nav(action: NavAction(req(urls.localHashed, defaultHeaders.allowingExtraKeys), .backForw(-1), from: history[7], src: main(urls.localHashed)), .approved, isCurrent: false))
        ])
    }

    func testJSHistoryManipulation() throws {
        let customCallbacksHandler = CustomCallbacksHandler()
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })), .weak(customCallbacksHandler))

        server.middleware = [{ [data] request in
            XCTAssertEqual(request.path, "/")
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        var eDidFinish = expectation(description: "onDidFinish 1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)
        responder(at: 0).clear()

        eDidFinish = expectation(description: "onDidFinish 2")

        var didPushStateCounter = 0
        let eDidSameDocumentNavigation = expectation(description: "onDidSameDocumentNavigation")
        customCallbacksHandler.didSameDocumentNavigation = { _, type in
            didPushStateCounter += 1
            if didPushStateCounter == 4 {
                eDidSameDocumentNavigation.fulfill()
            }
        }

        withWebView { webView in
            webView.evaluateJavaScript("history.pushState({page: 1}, '1', '/1')", in: nil, in: WKContentWorld.page) { _ in
                webView.evaluateJavaScript("history.pushState({page: 3}, '3', '/3')", in: nil, in: WKContentWorld.page) { _ in
                    webView.evaluateJavaScript("history.pushState({page: 2}, '2', '/2')", in: nil, in: WKContentWorld.page) { _ in
                        webView.evaluateJavaScript("history.go(-1)", in: nil, in: WKContentWorld.page) { _ in
                            eDidFinish.fulfill()
                        }
                    }
                }
            }
        }
        waitForExpectations(timeout: 5)

        // now navigate from pseudo "/3" to "/3#hashed"
        var eDidGoBack = expectation(description: "onDidGoToNamedLink")
        customCallbacksHandler.didSameDocumentNavigation = { _, type in
            if type == .sessionStatePop { eDidGoBack.fulfill() }
        }
        withWebView { webView in
            _=webView.load(req(urls.local3Hashed))
        }
        waitForExpectations(timeout: 5)

        // back
        eDidGoBack = expectation(description: "onDidGoBack")
        withWebView { webView in
            _=webView.goBack()
        }
        waitForExpectations(timeout: 5)

        // back
        eDidGoBack = expectation(description: "onDidGoBack 2")
        withWebView { webView in
            _=webView.goBack()
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .willStart(Nav(action: NavAction(req(urls.local3Hashed), .sameDocumentNavigation, from: history[1], src: main(urls.local3)), .approved, isCurrent: false))
        ])
    }

}

// swiftlint:enable unused_closure_parameter
// swiftlint:enable trailing_comma
// swiftlint:enable opening_brace

#endif
