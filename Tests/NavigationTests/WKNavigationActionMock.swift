//
//  WKNavigationActionMock.swift
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

import WebKit
@testable import Navigation

// swiftlint:disable identifier_name
// swiftlint:disable line_length

class WKNavigationActionMock: NSObject {

    @objc var sourceFrame: WKFrameInfo

    @objc var targetFrame: WKFrameInfo?

    @objc var navigationType: WKNavigationType

    @objc var request: URLRequest

    @objc var shouldPerformDownload: Bool = false

    @objc var modifierFlags: NSEvent.ModifierFlags

    @objc var buttonNumber: Int

    @objc var isUserInitiated: Bool

    @objc var mainFrameNavigation: Any?

    var navigationAction: WKNavigationAction {
        withUnsafePointer(to: self) { $0.withMemoryRebound(to: WKNavigationAction.self, capacity: 1) { $0 } }.pointee
    }

    init(sourceFrame: WKFrameInfo, targetFrame: WKFrameInfo? = nil, navigationType: WKNavigationType, request: URLRequest, isUserInitiated: Bool = false, shouldPerformDownload: Bool = false, modifierFlags: NSEvent.ModifierFlags = [], buttonNumber: Int = 0, mainFrameNavigation: Any? = nil) {
        self.sourceFrame = sourceFrame
        self.targetFrame = targetFrame
        self.navigationType = navigationType
        self.request = request
        self.shouldPerformDownload = shouldPerformDownload
        self.modifierFlags = modifierFlags
        self.buttonNumber = buttonNumber
        self.isUserInitiated = isUserInitiated
        self.mainFrameNavigation = mainFrameNavigation
    }

}

class WKFrameInfoMock: NSObject {

    @objc var isMainFrame: Bool

    @objc var request: URLRequest

    @objc var securityOrigin: WKSecurityOrigin

    @objc weak var webView: WKWebView?

    class FrameID: NSObject {
        @objc var frameID: String
        init(frameID: String) {
            self.frameID = frameID
        }
    }

    @objc var handle: FrameID {
        FrameID(frameID: isMainFrame ? WKFrameInfo.defaultMainFrameHandle : "9")
    }

    init(isMainFrame: Bool, request: URLRequest, securityOrigin: WKSecurityOrigin, webView: WKWebView?) {
        self.isMainFrame = isMainFrame
        self.request = request
        self.securityOrigin = securityOrigin
        self.webView = webView
    }

    var frameInfo: WKFrameInfo {
        withUnsafePointer(to: self) { $0.withMemoryRebound(to: WKFrameInfo.self, capacity: 1) { $0 } }.pointee
    }

}

extension WKFrameInfo {
    static func mock(for webView: WKWebView, isMain: Bool = true, request: URLRequest? = nil) -> WKFrameInfo {
        let url = request?.url ?? webView.url ?? .empty
        return WKFrameInfoMock(isMainFrame: isMain, request: request ?? URLRequest(url: .empty), securityOrigin: WKSecurityOriginMock.new(url: url), webView: webView).frameInfo
    }
}

@objc class WKSecurityOriginMock: WKSecurityOrigin {
    var _protocol: String!
    override var `protocol`: String { _protocol }
    var _host: String!
    override var host: String { _host }
    var _port: Int!
    override var port: Int { _port }

    internal func setURL(_ url: URL) {
        self._protocol = url.scheme ?? ""
        self._host = url.host ?? ""
        self._port = url.port ?? (url.scheme != nil ? (url.scheme == "https" ? 443 : 80) : 0)
    }

    class func new(url: URL) -> WKSecurityOriginMock {
        let mock = (self.perform(NSSelectorFromString("alloc")).takeUnretainedValue() as? WKSecurityOriginMock)!
        mock.setURL(url)
        return mock
    }

}
