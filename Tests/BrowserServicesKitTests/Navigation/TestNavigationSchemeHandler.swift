//
//  TestNavigationSchemeHandler.swift
//  DuckDuckGo
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import XCTest
import WebKit

final class TestNavigationSchemeHandler: NSObject, WKURLSchemeHandler {
    typealias RequestResponse = (URL) -> Data

    var requestHandlers = [URL: RequestResponse]()

    static let scheme = "test"

    public var onRequest: ((RedirectableWKURLSchemeTask) -> Void)?

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        self.onRequest?(urlSchemeTask.redirectable()) ?? {
            urlSchemeTask.didFailWithError(WKError(.unknown))
        }()
    }

    @objc
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) { }

}

extension WKURLSchemeTask {
    func redirectable() -> RedirectableWKURLSchemeTask {
        withUnsafePointer(to: self) { $0.withMemoryRebound(to: RedirectableWKURLSchemeTask?.self, capacity: 1) { $0 } }.pointee!
    }
}

@objc protocol RedirectableWKURLSchemeTask: WKURLSchemeTask {

    @objc(_willPerformRedirection:newRequest:completionHandler:)
    func willPerformRedirection(_ response: URLResponse, newRequest: URLRequest, completionHandler: @escaping (URLRequest) -> Void)
    @objc(_didPerformRedirection:newRequest:)
    func didPerformRedirection(_ response: URLResponse, newRequest: URLRequest)

}
