//
//  NavigationResponse.swift
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

// swiftlint:disable line_length
public struct NavigationResponse: Equatable {

    public let response: URLResponse

    public let isForMainFrame: Bool
    public let canShowMIMEType: Bool

    public init(response: URLResponse, isForMainFrame: Bool, canShowMIMEType: Bool) {
        self.response = response
        self.isForMainFrame = isForMainFrame
        self.canShowMIMEType = canShowMIMEType
    }

    init(navigationResponse: WKNavigationResponse) {
        self.init(response: navigationResponse.response, isForMainFrame: navigationResponse.isForMainFrame, canShowMIMEType: navigationResponse.canShowMIMEType)
    }

    public static func == (lhs: NavigationResponse, rhs: NavigationResponse) -> Bool {
        lhs.response.isEqual(to: rhs.response) && lhs.isForMainFrame == rhs.isForMainFrame && lhs.canShowMIMEType == rhs.canShowMIMEType
    }

}

extension NavigationResponse {

    public var url: URL {
        response.url!
    }

    public var httpResponse: HTTPURLResponse? {
        response as? HTTPURLResponse
    }

    public var httpStatusCode: Int? {
        httpResponse?.statusCode
    }

    public var shouldDownload: Bool {
        httpResponse?.shouldDownload ?? false
    }

}

private extension URLResponse {
    func isEqual(to other: URLResponse) -> Bool {
        guard url == other.url && mimeType == other.mimeType && expectedContentLength == other.expectedContentLength && textEncodingName == other.textEncodingName && suggestedFilename == other.suggestedFilename else { return false }
        if let lhs = self as? HTTPURLResponse, let rhs = other as? HTTPURLResponse {
            return lhs.statusCode == rhs.statusCode && lhs.allHeaderFields as NSDictionary == rhs.allHeaderFields as NSDictionary
        }
        return true
    }
}

extension NavigationResponse: CustomDebugStringConvertible {
    public var debugDescription: String {
        let statusCode = self.httpStatusCode.map { String.init($0) } ?? "-"
        return "<Response: \((response.url ?? NSURL() as URL).absoluteString) status:\(statusCode):\(shouldDownload ? " Download" : "")>"
    }
}

public enum NavigationResponsePolicy: String, Equatable {
    case allow
    case cancel
    case download
}

extension NavigationResponsePolicy? {
    /// Pass decision making to next responder
    public static let next = NavigationResponsePolicy?.none
}

extension WKNavigationResponsePolicy {
    static let download = WKNavigationResponsePolicy(rawValue: Self.allow.rawValue + 1) ?? .cancel
}
