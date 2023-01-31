//
//  Navigator.swift
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

import Foundation
import WebKit

@MainActor
public struct Navigator {

    let webView: WKWebView
    let distributedNavigationDelegate: DistributedNavigationDelegate

    init(webView: WKWebView, distributedNavigationDelegate: DistributedNavigationDelegate) {
        self.webView = webView
        self.distributedNavigationDelegate = distributedNavigationDelegate
    }

    init?(webView: WKWebView) {
        guard let distributedNavigationDelegate = webView.navigationDelegate as? DistributedNavigationDelegate else {
            assertionFailure("webView.navigationDelegate is not DistributedNavigationDelegate")
            return nil
        }
        self.init(webView: webView, distributedNavigationDelegate: distributedNavigationDelegate)
    }

    @discardableResult
    public func load(_ request: URLRequest, withExpectedNavigationType expectedNavigationType: NavigationType? = .redirect(.developer)) -> ExpectedNavigation? {
        webView.load(request)?
            .expectedNavigation(with: expectedNavigationType, distributedNavigationDelegate: distributedNavigationDelegate)
    }
    @discardableResult
    public func loadFileURL(_ url: URL, allowingReadAccessTo readAccessURL: URL, withExpectedNavigationType expectedNavigationType: NavigationType? = .redirect(.developer)) -> ExpectedNavigation? {
        webView.loadFileURL(url, allowingReadAccessTo: readAccessURL)?
            .expectedNavigation(with: expectedNavigationType, distributedNavigationDelegate: distributedNavigationDelegate)
    }
    @discardableResult
    public func loadHTMLString(_ string: String, baseURL: URL?, withExpectedNavigationType expectedNavigationType: NavigationType? = .redirect(.developer)) -> ExpectedNavigation? {
        webView.loadHTMLString(string, baseURL: baseURL)?
            .expectedNavigation(with: expectedNavigationType, distributedNavigationDelegate: distributedNavigationDelegate)
    }
    @discardableResult
    public func load(_ data: Data, mimeType MIMEType: String, characterEncodingName: String, baseURL: URL, withExpectedNavigationType expectedNavigationType: NavigationType? = .redirect(.developer)) -> ExpectedNavigation? {
        webView.load(data, mimeType: MIMEType, characterEncodingName: characterEncodingName, baseURL: baseURL)?
            .expectedNavigation(with: expectedNavigationType, distributedNavigationDelegate: distributedNavigationDelegate)
    }
    @discardableResult
    public func go(to item: WKBackForwardListItem, withExpectedNavigationType expectedNavigationType: NavigationType? = .redirect(.developer)) -> ExpectedNavigation? {
        webView.go(to: item)?
            .expectedNavigation(with: expectedNavigationType, distributedNavigationDelegate: distributedNavigationDelegate)
    }
    @discardableResult
    public func goBack(withExpectedNavigationType expectedNavigationType: NavigationType? = .redirect(.developer)) -> ExpectedNavigation? {
        webView.goBack()?
            .expectedNavigation(with: expectedNavigationType, distributedNavigationDelegate: distributedNavigationDelegate)
    }
    @discardableResult
    public func goForward(withExpectedNavigationType expectedNavigationType: NavigationType? = .redirect(.developer)) -> ExpectedNavigation? {
        webView.goForward()?
            .expectedNavigation(with: expectedNavigationType, distributedNavigationDelegate: distributedNavigationDelegate)
    }
    @discardableResult
    public func reload(withExpectedNavigationType expectedNavigationType: NavigationType? = .redirect(.developer)) -> ExpectedNavigation? {
        webView.reload()?
            .expectedNavigation(with: expectedNavigationType, distributedNavigationDelegate: distributedNavigationDelegate)
    }
    @discardableResult
    public func reloadFromOrigin(withExpectedNavigationType expectedNavigationType: NavigationType? = .redirect(.developer)) -> ExpectedNavigation? {
        webView.reloadFromOrigin()?
            .expectedNavigation(with: expectedNavigationType, distributedNavigationDelegate: distributedNavigationDelegate)
    }

    @available(macOS 12.0, *)
    @discardableResult
    public func loadFileRequest(_ request: URLRequest, allowingReadAccessTo readAccessURL: URL, withExpectedNavigationType expectedNavigationType: NavigationType? = .redirect(.developer)) -> ExpectedNavigation {
        webView.loadFileRequest(request, allowingReadAccessTo: readAccessURL)
            .expectedNavigation(with: expectedNavigationType, distributedNavigationDelegate: distributedNavigationDelegate)
    }

    @available(macOS 12.0, *)
    @discardableResult
    public func loadSimulatedRequest(_ request: URLRequest, response: URLResponse, responseData data: Data, withExpectedNavigationType expectedNavigationType: NavigationType? = .redirect(.developer)) -> ExpectedNavigation {
        webView.loadSimulatedRequest(request, response: response, responseData: data)
            .expectedNavigation(with: expectedNavigationType, distributedNavigationDelegate: distributedNavigationDelegate)
    }

    @available(macOS 12.0, *)
    @discardableResult
    public func loadSimulatedRequest(_ request: URLRequest, responseHTML string: String, withExpectedNavigationType expectedNavigationType: NavigationType? = .redirect(.developer)) -> ExpectedNavigation {
        webView.loadSimulatedRequest(request, responseHTML: string)
            .expectedNavigation(with: expectedNavigationType, distributedNavigationDelegate: distributedNavigationDelegate)
    }

}

@MainActor
public class ExpectedNavigation {

    internal let navigation: Navigation

    internal init(navigation: Navigation) {
        self.navigation = navigation
    }

    public var navigationResponders: ResponderChain {
        get {
            navigation.navigationResponders
        }
        _modify {
            yield &navigation.navigationResponders
        }
    }

}
extension ExpectedNavigation: NavigationProtocol {}

extension WKNavigation {

    @MainActor
    func expectedNavigation(with expectedNavigationType: NavigationType?, distributedNavigationDelegate: DistributedNavigationDelegate) -> ExpectedNavigation {
        let navigation = Navigation(identity: NavigationIdentity(self), responders: distributedNavigationDelegate.responders, state: .expected(expectedNavigationType), isCurrent: false)
        self.navigation = navigation
        return ExpectedNavigation(navigation: navigation)
    }

}

extension WKWebView {

    func navigator(distributedNavigationDelegate: DistributedNavigationDelegate) -> Navigator {
        Navigator(webView: self, distributedNavigationDelegate: distributedNavigationDelegate)
    }

}
