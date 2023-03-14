//
//  FrameInfo.swift
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
import Foundation
import WebKit

// swiftlint:disable line_length
public struct FrameInfo: Equatable {

    public weak var webView: WKWebView?
    public let handle: FrameHandle

    public let isMainFrame: Bool
    public let url: URL
    public let securityOrigin: SecurityOrigin

    public init(webView: WKWebView?, handle: FrameHandle, isMainFrame: Bool, url: URL, securityOrigin: SecurityOrigin) {
        self.webView = webView
        self.handle = handle
        self.isMainFrame = isMainFrame
        self.url = url
        self.securityOrigin = securityOrigin
    }

    public init(frame: WKFrameInfo) {
        self.init(webView: frame.webView, handle: frame.handle, isMainFrame: frame.isMainFrame, url: frame.safeRequest?.url ?? .empty, securityOrigin: SecurityOrigin(frame.securityOrigin))
    }

    public static func mainFrame(for webView: WKWebView) -> FrameInfo {
        FrameInfo(webView: webView,
                  handle: webView.mainFrameHandle,
                  isMainFrame: true,
                  url: webView.url ?? .empty,
                  securityOrigin: webView.url?.securityOrigin ?? .empty)
    }

    public static func == (lhs: FrameInfo, rhs: FrameInfo) -> Bool {
        return lhs.handle == rhs.handle && lhs.webView == rhs.webView && lhs.isMainFrame == rhs.isMainFrame && lhs.url.matches(rhs.url) && lhs.securityOrigin == rhs.securityOrigin
    }

}

extension SecurityOrigin {
    public init(_ securityOrigin: WKSecurityOrigin) {
        self.init(protocol: securityOrigin.protocol, host: securityOrigin.host, port: securityOrigin.port)
    }
}

extension FrameInfo: CustomDebugStringConvertible {
    public var debugDescription: String {
        let webViewPtr = webView.map(NSValue.init(nonretainedObject:))?.pointerValue?.debugDescription.replacing(regex: "^0x0*", with: "0x") ?? "<nil>"
        return "<Frame \(webViewPtr)_\(handle.debugDescription) \(isMainFrame ? ": Main" : ""); current url: \(url.absoluteString.isEmpty ? "empty" : url.absoluteString)>"
    }
}
