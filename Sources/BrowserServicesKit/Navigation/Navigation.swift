//
//  Navigation.swift
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

import Foundation
import WebKit
import Common

public class Navigation: Equatable {
    fileprivate var navigation: WKNavigation?

    public private(set) var navigationAction: NavigationAction
    public private(set) var state: NavigationState
    public private(set) var isCommitted: Bool = false
    public private(set) var isSimulated: Bool?

    public var userInfo = UserInfo()

    private init(navigationAction: NavigationAction, state: NavigationState, navigation: WKNavigation?) {
        self.navigationAction = navigationAction
        self.state = state
        self.navigation = navigation
        assert(navigationAction.navigationType.previousNavigation !== self)
    }

    static func expected(navigationAction: NavigationAction, current navigation: Navigation?) -> Navigation {
        let wkNavigation: WKNavigation?
        if case .redirect(type: .client, previousNavigation: _) = navigationAction.navigationType {
            // new WKNavigation starts for js redirects
            wkNavigation = nil
        } else {
            // the same WKNavigation is continued for server redirects
            wkNavigation = navigation?.navigation
        }

        return Navigation(navigationAction: navigationAction, state: .expected, navigation: wkNavigation)
    }

    static func started(navigationAction: NavigationAction, navigation: WKNavigation?) -> Navigation {
        Navigation(navigationAction: navigationAction, state: .started, navigation: navigation)
    }

    func matches(_ navigation: WKNavigation?) -> Bool {
        self.navigation === navigation
    }

    public var request: URLRequest {
        navigationAction.request
    }

    public var url: URL {
        navigationAction.url
    }

    public static func == (lhs: Navigation, rhs: Navigation) -> Bool {
        lhs === rhs
    }

    deinit {
        // clear nested redirect navigations asynchronously to avoid stack overflow
        if case .redirect(type: _, previousNavigation: .some(let previousNavigation)) = navigationAction.navigationType,
           case .redirect(type: _, previousNavigation: .some(let nestedPreviousNavigation)) = previousNavigation.navigationAction.navigationType {
            DispatchQueue.main.async {
                withExtendedLifetime(nestedPreviousNavigation, {})
            }
        }
    }

}

public enum NavigationState: Equatable {
    case expected
    case started
    case awaitingFinishOrClientRedirect

    case awaitingRedirect(type: RedirectType, url: URL?)
    case redirected

    case responseReceived(URLResponse)
    case finished
    case failed(WKError)

    var isResponseReceived: Bool {
        if case .responseReceived = self { return true }
        return false
    }
}

public enum RedirectType: Equatable {
    case client(delay: TimeInterval)
    case server
}

extension Navigation {

    func started(_ navigation: WKNavigation) {
        assert(self.navigation == nil)
        self.navigation = navigation
        guard case .expected = self.state else {
            assertionFailure("unexpected state \(self.state)")
            return

        }
        self.state = .started
    }

    func committed() {
        switch state {
        case .responseReceived:
            self.isSimulated = false
        case .started:
            self.isSimulated = true
        case .expected,
             .awaitingFinishOrClientRedirect,
             .awaitingRedirect,
             .redirected,
             .finished,
             .failed:
            assertionFailure("unexpected state \(self.state)")
            break
        }

        self.isCommitted = true
    }

    func receivedResponse(_ response: URLResponse) {
        assert(state == .started)
        self.state = .responseReceived(response)
    }

    // Shortly after receiving webView:didFinishNavigation: a client redirect navigation may start
    func willFinish() {
        switch self.state {
        case .started:
            assert(self.isSimulated == true)
            self.state = .awaitingFinishOrClientRedirect
        case .responseReceived:
            // regular flow
            self.state = .awaitingFinishOrClientRedirect
        case .awaitingRedirect:
            // state after willPerformClientRedirectToURL, redirect expected:
            break
        case .expected, .awaitingFinishOrClientRedirect, .redirected, .finished, .failed:
            assertionFailure("unexpected state \(self.state)")
        }
    }

    // On the next RunLop pass we can finish the navigation
    func didFinish() {
        if case .redirected = state { return } // new navigation has started
        assert(state == .awaitingFinishOrClientRedirect)
        self.state = .finished
    }

    func didFail(with error: WKError) {
        assert(state == .started)
        self.state = .failed(error)
    }

    func willPerformClientRedirect(to url: URL, delay: TimeInterval) {
        assert(state.isResponseReceived)
        self.state = .awaitingRedirect(type: .client(delay: delay), url: url)
    }

    func didReceiveServerRedirect(navigation: WKNavigation?) {
        assert(state == .expected)
        if let navigation {
            assert(self.navigation == nil || self.navigation === navigation)
            self.navigation = navigation
        }
        self.state = .started
    }

    func redirectType(for navigationAction: WKNavigationAction) -> RedirectType? {
        switch state {
        case .awaitingRedirect(type: let redirectType, url: let redirectUrl):
            // handle expected redirect
            if redirectUrl == nil || redirectUrl!.matches(navigationAction.request.url!) {
                return redirectType
            }
            return nil
        case .started:
            // handle server redirect
            return .server

        case .redirected:
            assertionFailure("unexpected state \(self.state)")
            fallthrough
        case .awaitingFinishOrClientRedirect:
            // handle client (js) redirect
            return .client(delay: 0)

        case .expected, .responseReceived, .finished, .failed:
            // unexpected redirect
            return nil
        }
    }

    func redirected() {
        switch state {
        case  .started, .awaitingRedirect, .awaitingFinishOrClientRedirect:
            self.state = .redirected
        case .expected, .responseReceived, .finished, .failed, .redirected:
            assertionFailure("unexpected state \(self.state)")
        }
    }

}

extension Navigation: CustomDebugStringConvertible {
    public var debugDescription: String {
        let navigationDescription = navigation.debugDescription.dropping(prefix: "<WK").dropping(suffix: ">")
        return "<\(navigationDescription): \(isSimulated == true ? "simulated " : "")url: \"\(url.absoluteString)\" state: \(state)\(isCommitted ? "(committed)" : "") type: \(navigationAction.navigationType)>"
    }
}

extension RedirectType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .client(delay: let delay): return "client" + (delay > 0 ? "(delay: \(delay))" : "")
        case .server: return "server"
        }
    }
}
