//
//  NavigationDownloadsTests.swift
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
class  NavigationDownloadsTests: DistributedNavigationDelegateTestsBase {

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

        withWebView { webView in
            _=webView.load(URLRequest(url: urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .navActionWillBecomeDownload(navAct(1)),
            .navActionBecameDownload(navAct(1), urls.local)
        ])
    }

    func testDownloadNavigationActionFromFrame() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        navigationDelegateProxy.finishEventsDispatchTime = .afterDidStartNavigationAction
        server.middleware = [{ [data] request in
            guard request.path == "/" else { return nil }
            return .ok(.html(data.htmlWithIframe3.string()!))
        }, { [data, urls] request in
            guard request.path == urls.local3.path else { return nil }
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        var frameHandle: String!
        responder(at: 0).onNavigationAction = { [urls] navAction, _ in
            if navAction.url.path == urls.local3.path {
                frameHandle = navAction.targetFrame.identity.handle
                XCTAssertNotEqual(frameHandle, WKFrameInfo.defaultMainFrameHandle)
                return .download
            }
            return .next
        }
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
        }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .navigationActionReceived, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.htmlWithIframe3.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),

            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(WKFrameInfo.defaultMainFrameHandle, urls.local), targ: frame(frameHandle, .empty, secOrigin: urls.local.securityOrigin)),
            .navActionWillBecomeDownload(navAct(2)),

            .navActionBecameDownload(navAct(2), urls.local3),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed))
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
        responder(at: 0).onNavigationResponse = { _ in
                .download
        }
        let eDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { _, _ in
            eDidFail.fulfill()
        }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .navigationActionReceived, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Encoding": "gzip, deflate", "Accept-Language": "en-XX,en;q=0.9", "Upgrade-Insecure-Requests": "1"]), .redirect(.server), redirects: [navAct(1)], src: main()),
            .willStart(Nav(action: navAct(2), redirects: [navAct(1)], .redirected(.server))),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local2, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .navResponseWillBecomeDownload(0),
            .navResponseBecameDownload(0, urls.local2),

            .didFail(Nav(action: navAct(2), redirects: [navAct(1)], .failed(WKError(.frameLoadInterruptedByPolicyChange)), resp: resp(0), isCurrent: false), WKError.Code.frameLoadInterruptedByPolicyChange.rawValue)

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

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        var frameHandle: String!
        responder(at: 0).onNavigationAction = { [urls] navAction, _ in
            if navAction.url.path == urls.local1.path {
                frameHandle = navAction.targetFrame.identity.handle
                XCTAssertNotEqual(frameHandle, WKFrameInfo.defaultMainFrameHandle)
            }
            return .next
        }
        responder(at: 0).onNavigationResponse = { _ in
                .download
        }
        let eDidFailLoadingFrame = expectation(description: "didFailLoadingFrame")
        didFinishLoadingFrameHandler.didFailProvisionalLoadInFrame = { request, frame, _ in
            eDidFailLoadingFrame.fulfill()
        }
        responder(at: 0).clear()
        withWebView { webView in
            webView.evaluateJavaScript("window.frames[0].location.href = '\(urls.local1.string)'")
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local1, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(WKFrameInfo.defaultMainFrameHandle, urls.local), targ: frame(frameHandle, urls.local3)),
            .response(.resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"], .nonMain), nil),
            .navResponseWillBecomeDownload(2),
            .navResponseBecameDownload(2, urls.local1)
        ])
    }

    // TODO: multiple download actions

}
