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

// swiftlint:disable line_length
// swiftlint:disable function_body_length
// swiftlint:disable unused_closure_parameter
// swiftlint:disable type_body_length
// swiftlint:disable opening_brace
// swiftlint:disable force_try
// swiftlint:disable trailing_comma

@available(macOS 12.0, iOS 15.0, *)
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
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.htmlWithIframe3.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),

            .navigationAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(WKFrameInfo.defaultMainFrameHandle, urls.local), targ: frame(frameHandle, .empty, secOrigin: urls.local.securityOrigin)),
            .navActionWillBecomeDownload(navAct(2)),

            .navActionBecameDownload(navAct(2), urls.local3),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),
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
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Encoding": "gzip, deflate", "Accept-Language": "en-XX,en;q=0.9", "Upgrade-Insecure-Requests": "1"]), .redirect(.server), redirects: [navAct(1)], src: main()),
            .didReceiveRedirect(Nav(action: navAct(2), redirects: [navAct(1)], .started)),
            .response(Nav(action: navAct(2), redirects: [navAct(1)], .responseReceived, resp: .resp(urls.local2, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .navResponseWillBecomeDownload(0),
            .navResponseBecameDownload(0, urls.local2),

            .didFail(Nav(action: navAct(2), redirects: [navAct(1)], .failed(WKError(.frameLoadInterruptedByPolicyChange)), resp: resp(0), isCurrent: false), WKError.Code.frameLoadInterruptedByPolicyChange.rawValue),
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
            .navResponseBecameDownload(2, urls.local1),
        ])
    }

    func testMultipleDownloadNavigationActions() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        navigationDelegateProxy.finishEventsDispatchTime = .afterDidStartNavigationAction

        server.middleware = [{ [data] request in
            guard request.path == "/" else { return nil }
            return .ok(.html(data.htmlWith3iFrames.string()!))
        }, { [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        var frameHandles = [String: String]()
        responder(at: 0).onNavigationAction = { [urls] navAction, _ in
            guard navAction.url.matches(urls.local) else {
                frameHandles[navAction.url.path] = navAction.targetFrame.identity.handle
                XCTAssertNotEqual(navAction.targetFrame.identity.handle, WKFrameInfo.defaultMainFrameHandle)
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

        // sort navActionBecameDownload by url
        responder(at: 0).history
            .replaceSubrange(11...13, with: responder(at: 0)
                .history[11...13]
                .sorted {
                    guard case .navActionBecameDownload(_, let url1, _) = $0, case .navActionBecameDownload(_, let url2, _) = $1 else {
                        XCTFail("unexpected \($0) or \($1)")
                        return false
                    }

                    return Int(String(url1.last!))! < Int(String(url2.last!))!
                })

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.htmlWith3iFrames.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),

            .navigationAction(NavAction(req(urls.local2, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(WKFrameInfo.defaultMainFrameHandle, urls.local), targ: frame(frameHandles[urls.local2.path]!, .empty, secOrigin: urls.local.securityOrigin))),
            .navActionWillBecomeDownload(navAct(2)),

            .navigationAction(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(WKFrameInfo.defaultMainFrameHandle, urls.local), targ: frame(frameHandles[urls.local3.path]!, .empty, secOrigin: urls.local.securityOrigin))),
            .navActionWillBecomeDownload(navAct(3)),

            .navigationAction(NavAction(req(urls.local4, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(WKFrameInfo.defaultMainFrameHandle, urls.local), targ: frame(frameHandles[urls.local4.path]!, .empty, secOrigin: urls.local.securityOrigin))),
            .navActionWillBecomeDownload(navAct(4)),

            .navActionBecameDownload(navAct(2), urls.local2),
            .navActionBecameDownload(navAct(3), urls.local3),
            .navActionBecameDownload(navAct(4), urls.local4),

            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),
        ])
    }

    func testMultipleDownloadNavigationResponses() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        navigationDelegateProxy.finishEventsDispatchTime = .afterDidStartNavigationAction

        server.middleware = [{ [data] request in
            guard request.path == "/" else { return nil }
            return .ok(.html(data.htmlWith3iFrames.string()!))
        }, { [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        var frameHandles = [String: String]()
        responder(at: 0).onNavigationAction = { [urls] navAction, _ in
            if !navAction.url.matches(urls.local) {
                frameHandles[navAction.url.path] = navAction.targetFrame.identity.handle
                XCTAssertNotEqual(navAction.targetFrame.identity.handle, WKFrameInfo.defaultMainFrameHandle)
            }
            return .allow
        }
        responder(at: 0).onNavigationResponse = { [urls] navResponse in
            guard navResponse.url.matches(urls.local) else {
                return .download
            }
            return .allow
        }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
        }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        // sort download events by url and event order
        responder(at: 0).history
            .replaceSubrange(8...16, with: responder(at: 0)
                .history[8...16]
                .sorted {
                    func eventAndUrlIdx(from event: TestsNavigationEvent) -> (event: Int, idx: Int) {
                        switch event {
                        case .navigationResponse(.response(let response, _), _):
                            return (0, Int(String(response.response.url.string.last!))!)
                        case .navResponseWillBecomeDownload(let idx, _):
                            return (1, idx + 1)
                        case .navResponseBecameDownload(_, let url, _):
                            return (2, Int(String(url.string.last!))!)
                        default:
                            XCTFail("unexpected \(event)")
                            return (0, 0)
                        }
                    }
                    let lhs = eventAndUrlIdx(from: $0)
                    let rhs = eventAndUrlIdx(from: $1)
                    if lhs.idx == rhs.idx {
                        return lhs.event < rhs.event
                    } else {
                        return lhs.idx < rhs.idx
                    }
                })

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.htmlWith3iFrames.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),

            .navigationAction(NavAction(req(urls.local2, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(WKFrameInfo.defaultMainFrameHandle, urls.local), targ: frame(frameHandles[urls.local2.path]!, .empty, secOrigin: urls.local.securityOrigin))),
            .navigationAction(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(WKFrameInfo.defaultMainFrameHandle, urls.local), targ: frame(frameHandles[urls.local3.path]!, .empty, secOrigin: urls.local.securityOrigin))),
            .navigationAction(NavAction(req(urls.local4, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: frame(WKFrameInfo.defaultMainFrameHandle, urls.local), targ: frame(frameHandles[urls.local4.path]!, .empty, secOrigin: urls.local.securityOrigin))),

            .response(.resp(urls.local2, data.html.count, headers: .default + ["Content-Type": "text/html"], .nonMain), Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .navResponseWillBecomeDownload(1),
            .navResponseBecameDownload(response(matching: urls.local2), urls.local2),

            .response(.resp(urls.local3, data.html.count, headers: .default + ["Content-Type": "text/html"], .nonMain), Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .navResponseWillBecomeDownload(2),
            .navResponseBecameDownload(response(matching: urls.local3), urls.local3),

            .response(.resp(urls.local4, data.html.count, headers: .default + ["Content-Type": "text/html"], .nonMain), Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .navResponseWillBecomeDownload(3),
            .navResponseBecameDownload(response(matching: urls.local4), urls.local4),

            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),
        ])
    }

    func testDownloadCancellation() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        let eDidFinish = expectation(description: "onDidFinish")

        responder(at: 0).onNavigationAction = { _, _ in .download }
        responder(at: 0).onNavActionBecameDownload = { _, download in
            (download as WebKitDownload).cancel { _ in
                eDidFinish.fulfill()
            }
        }

        withWebView { webView in
            _=webView.load(URLRequest(url: urls.local))
        }
        waitForExpectations(timeout: 5)
    }

}
