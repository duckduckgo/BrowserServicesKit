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
    private let frameInfo: WKFrameInfo?
    public let isMainFrame: Bool

    public let request: URLRequest?
    public let securityOrigin: SecurityOrigin

    public static let main = FrameInfo(frameInfo: nil, isMainFrame: true, request: nil, securityOrigin: .empty)

    internal init(frameInfo: WKFrameInfo?, isMainFrame: Bool, request: URLRequest?, securityOrigin: SecurityOrigin) {
        self.frameInfo = frameInfo
        self.isMainFrame = isMainFrame
        self.request = request
        self.securityOrigin = securityOrigin
    }

    internal init(_ frameInfo: WKFrameInfo) {
        self.init(frameInfo: frameInfo, isMainFrame: frameInfo.isMainFrame, request: frameInfo.request, securityOrigin: .init(frameInfo.securityOrigin))
    }

    public var url: URL? {
        request?.url
    }

}

public struct SecurityOrigin: Hashable {
    public let `protocol`: String
    public let host: String
    public let port: Int

    public init(`protocol`: String, host: String, port: Int) {
        self.`protocol` = `protocol`
        self.host = host
        self.port = port
    }

    internal init(_ securityOrigin: WKSecurityOrigin) {
        self.init(protocol: securityOrigin.protocol, host: securityOrigin.host, port: securityOrigin.port)
    }

    public static let empty = SecurityOrigin(protocol: "", host: "", port: 0)
}

extension FrameInfo: CustomDebugStringConvertible {
    public var debugDescription: String {
        "<Frame #\(frameInfo.map { $0.debug_handle } ?? "??")\(isMainFrame ? ": Main" : "")>"
    }
}

public extension WKFrameInfo {
    var debug_handle: String {
#if DEBUG
        String(describing: (self.value(forKey: "_handle") as? NSObject)!.value(forKey: "frameID")!)
#else
        "??"
#endif
    }
}
