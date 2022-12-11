//
//  AuthChallengeDisposition.swift
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

public struct FrameInfo: Equatable {
    public let identity: FrameIdentity
    public let url: URL
    public let securityOrigin: SecurityOrigin

    public init(frameIdentity: FrameIdentity, url: URL, securityOrigin: SecurityOrigin) {
        self.identity = frameIdentity
        self.url = url
        self.securityOrigin = securityOrigin
    }

    public init(frame: WKFrameInfo) {
        self.init(frameIdentity: FrameIdentity(frame), url: frame.request.url ?? NSURL() as URL, securityOrigin: SecurityOrigin(frame.securityOrigin))
    }

    public static func mainFrame(for webView: WKWebView) -> FrameInfo {
        FrameInfo(frameIdentity: .mainFrameIdentity(for: webView),
                  url: webView.url ?? NSURL() as URL,
                  securityOrigin: webView.url?.securityOrigin ?? .empty)
    }

}

extension FrameInfo {

    public var isMainFrame: Bool {
        identity.isMainFrame
    }

}

public struct FrameIdentity: Hashable {
    public typealias WebViewIdentity = NSValue

    public let webView: WebViewIdentity?
    public var handle: String
    public let isMainFrame: Bool

    public init(handle: String, webViewIdentity: WebViewIdentity?, isMainFrame: Bool) {
        self.handle = handle
        self.webView = webViewIdentity
        self.isMainFrame = isMainFrame
    }

    public init(_ frame: WKFrameInfo) {
        self.init(handle: frame.handle,
                  webViewIdentity: frame.webView.map(WebViewIdentity.init(nonretainedObject:)),
                  isMainFrame: frame.isMainFrame)
    }

    public static func mainFrameIdentity(for webView: WKWebView) -> FrameIdentity {
        self.init(handle: "4", webViewIdentity: WebViewIdentity(nonretainedObject: webView), isMainFrame: true)
    }

    public static func == (lhs: FrameIdentity, rhs: FrameIdentity) -> Bool {
        return lhs.handle == rhs.handle && lhs.webView == rhs.webView && lhs.isMainFrame == rhs.isMainFrame
    }

}

extension SecurityOrigin {
    public init(_ securityOrigin: WKSecurityOrigin) {
        self.init(protocol: securityOrigin.protocol, host: securityOrigin.host, port: securityOrigin.port)
    }
}

extension FrameInfo: CustomDebugStringConvertible {
    public var debugDescription: String {
        "<Frame \(identity.debugDescription); current url: \(url.absoluteString.isEmpty ? "empty" : url.absoluteString)>"
    }
}
extension FrameIdentity: CustomDebugStringConvertible {
    public var debugDescription: String {
        "\(webView?.pointerValue?.debugDescription.replacing(regex: "^0x0*", with: "0x") ?? "<nil>")_\(handle)\(isMainFrame ? ": Main" : "")"
    }
}

public extension WKFrameInfo {
    static var defaultMainFrameHandle = "4"

    var handle: String {
#if DEBUG
        String(describing: (self.value(forKey: "_handle") as? NSObject)!.value(forKey: "frameID")!)
#else
        self.isMainFrame ? Self.mainFrameHandle : "iframe"
#endif
    }
}
