//
//  NavigationRespondse.swift
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

public struct NavigationResponse: Equatable {

    private let navigationResponse: WKNavigationResponse
    let navigation: Navigation?

    internal init(navigationResponse: WKNavigationResponse, navigation: Navigation?) {
        self.navigationResponse = navigationResponse
        self.navigation = navigation
    }

    public var url: URL {
        navigationResponse.response.url!
    }

    public var isForMainFrame: Bool {
        navigationResponse.isForMainFrame
    }

    public var response: URLResponse {
        navigationResponse.response
    }

    public var canShowMIMEType: Bool {
        navigationResponse.canShowMIMEType
    }

    public var shouldDownload: Bool {
        response.shouldDownload
    }

}

public extension URLResponse {

    var shouldDownload: Bool {
        let contentDisposition = (self as? HTTPURLResponse)?.allHeaderFields["Content-Disposition"] as? String
        return contentDisposition?.hasPrefix("attachment") ?? false
    }

}

extension NavigationResponse: CustomDebugStringConvertible {
    public var debugDescription: String {
        let statusCode = { (self.navigationResponse.response as? HTTPURLResponse)?.statusCode }().map(String.init) ?? "??"
        return "<NavigationResponse: \(statusCode):\(shouldDownload ? " Download" : "") \"\(navigation?.debugDescription ?? "<nil>")\">"
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
