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

// swiftlint:disable line_length
public struct Navigation: Equatable {
    fileprivate(set) var identity: NavigationIdentity

    public private(set) var navigationAction: NavigationAction
    public private(set) var state: NavigationState
    public private(set) var isCommitted: Bool = false
    public private(set) var isSimulated: Bool?
    /// contains distance from `webView.backForwardList.currentItem` to a navigated item (if `navigationAction.navigationType` is `backForward`)
    /// negative for back navigations, positive for forward navigations
    public private(set) var backForwardNavigationDistance: Int?

    public init(navigationAction: NavigationAction, state: NavigationState = .expected, identity: NavigationIdentity = .expected, isCommitted: Bool = false, isSimulated: Bool? = nil, backForwardNavigationDistance: Int? = nil) {
        assert(backForwardNavigationDistance == nil || navigationAction.navigationType.isBackForward)

        self.navigationAction = navigationAction
        self.state = state
        self.identity = identity
        self.isCommitted = isCommitted
        self.isSimulated = (isCommitted && isSimulated == nil) ? (state == .started ? true : false) : isSimulated
        self.backForwardNavigationDistance = backForwardNavigationDistance
    }

    static func expected(navigationAction: NavigationAction, current navigation: Navigation?) -> Navigation {
        let identity: NavigationIdentity?
        switch navigationAction.navigationType {
        case .redirect(type: .client, history: _, initial: _):
            // new WKNavigation starts for js redirects
            identity = nil
        case .redirect(type: .server, history: _, initial: _):
            // the same WKNavigation is continued for server redirects
            identity = navigation?.identity
        case .reload, .backForward, .formSubmitted, .formResubmitted, .linkActivated,
             .custom, .sessionRestoration, .unknown, .userInitatedJavascriptNavigation:
            // not a redirect
            identity = nil
        }

        return Navigation(navigationAction: navigationAction, state: .expected, identity: identity ?? .expected)
    }

    static func started(navigationAction: NavigationAction, navigation wkNavigation: WKNavigation?) -> Navigation {
        var navigation = Navigation(navigationAction: navigationAction, state: .expected, identity: .expected)
        navigation.started(wkNavigation, backForwardNavigationDistance: nil)
        return navigation
    }

    public var request: URLRequest {
        navigationAction.request
    }

    public var url: URL {
        navigationAction.url
    }

    public var redirectHistory: [URL]? {
        navigationAction.navigationType.redirectHistory
    }

    public static func == (lhs: Navigation, rhs: Navigation) -> Bool {
        lhs.identity == rhs.identity && lhs.navigationAction == rhs.navigationAction && lhs.state == rhs.state && lhs.isCommitted == rhs.isCommitted && lhs.isSimulated == rhs.isSimulated && lhs.backForwardNavigationDistance == rhs.backForwardNavigationDistance
    }

}

public enum NavigationState: Equatable {
    case expected
    case started
    case awaitingFinishOrClientRedirect

    case awaitingRedirect(type: RedirectType, url: URL?)
    case redirected

    case responseReceived(NavigationResponse)
    case finished
    case failed(WKError)

    public var isResponseReceived: Bool {
        if case .responseReceived = self { return true }
        return false
    }
}

public enum RedirectType: Equatable {
    case client(delay: TimeInterval)
    case server
}

extension RedirectType {
    public var isClient: Bool {
        if case .client = self { return true }
        return false
    }
}

public struct NavigationIdentity: Equatable {

    private var value: AnyObject?

    public init(_ value: AnyObject?) {
        self.value = value
    }

    public static var expected = NavigationIdentity(nil)

    // used for tests to bind the identity to a first resolved navigation on first comparison
    // since test expectation may have no idea of a real WKNavigation object provided by WebView
    public static var autoresolvedOnFirstCompare = NavigationIdentity(AutoresolvedValueBox())
    private class AutoresolvedValueBox {
        var value: AnyObject?
    }

    fileprivate var isEmpty: Bool {
        value == nil
    }

    fileprivate mutating func resolve(with navigation: WKNavigation?) {
        assert(self.isEmpty || self.value === navigation)
        self.value = navigation
    }

    // on first test expectation comparison set value of boxed AutoresolvedValueBox
    private func valueResolvingIfNeeded(from other: NavigationIdentity?) -> AnyObject? {
#if DEBUG
        guard let autoresolved = self.value as? AutoresolvedValueBox else { return self.value }
        if let value = autoresolved.value {
            return value
        }
        guard let resolved = other?.valueResolvingIfNeeded(from: nil) else {
            assertionFailure("comparing 2 empty autoresolved values")
            return nil
        }
        autoresolved.value = resolved
        return resolved
#else
        return value
#endif
    }

    public static func == (lhs: NavigationIdentity, rhs: NavigationIdentity) -> Bool {
        return lhs.valueResolvingIfNeeded(from: rhs) === rhs.valueResolvingIfNeeded(from: lhs)
    }

}

extension Navigation {

    mutating func started(_ navigation: WKNavigation?, backForwardNavigationDistance: Int?) {
        assert(backForwardNavigationDistance != 0)

        self.identity.resolve(with: navigation)
        self.backForwardNavigationDistance = backForwardNavigationDistance

        guard case .expected = self.state else {
            assertionFailure("unexpected state \(self.state)")
            return
        }

        self.state = .started
    }

    mutating func committed(_ navigation: WKNavigation?) {
        self.identity.resolve(with: navigation)

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
        }

        self.isCommitted = true
    }

    mutating func receivedResponse(_ response: NavigationResponse) {
        assert(state == .started)
        self.state = .responseReceived(response)
    }

    mutating func willFinish(_ navigation: WKNavigation?) {
        self.identity.resolve(with: navigation)

        switch self.state {
        case .started:
            assert(self.isSimulated == true, "unexpected willFinish without didCommit")
            // Shortly after receiving webView:didFinishNavigation: a client redirect navigation may start
            self.state = .awaitingFinishOrClientRedirect
        case .responseReceived:
            // regular flow
            self.state = .awaitingFinishOrClientRedirect
        case .awaitingRedirect:
            // state after willPerformClientRedirectToURL, redirect expected
            break
        case .expected, .awaitingFinishOrClientRedirect, .redirected, .finished, .failed:
            assertionFailure("unexpected state \(self.state)")
        }
    }

    // On the next pass after `willFinish` we can finish the navigation
    mutating func didFinish() {
        assert(state == .awaitingFinishOrClientRedirect)
        self.state = .finished
    }

    mutating func didFail(_ navigation: WKNavigation? = nil, with error: WKError) {
        assert(state != .expected, "non-started navigations should‘t receive didFail")
        if let navigation {
            self.identity.resolve(with: navigation)
        }
        self.state = .failed(error)
    }

    mutating func willPerformClientRedirect(to url: URL, delay: TimeInterval) {
        assert(state.isResponseReceived)
        self.state = .awaitingRedirect(type: .client(delay: delay), url: url)
    }

    mutating func didReceiveServerRedirect(for navigation: WKNavigation?) {
        assert(state == .expected, "didReceiveServerRedirect should happen after decidePolicyForNavigationAction")
        self.identity.resolve(with: navigation)
        self.state = .started
    }

    func redirectType(for url: URL) -> RedirectType? {
        switch state {
        case .awaitingRedirect(type: let redirectType, url: let awaitedRedirectUrl):
            // handle expected redirect
            if awaitedRedirectUrl?.matches(url) == true || awaitedRedirectUrl == nil {
                return redirectType
            }
            // redirect was expected but for a different url, make a new Navigation just in case
            return nil
        case .started:
            // handle server redirect (after didStartNavigation)
            return .server

        case .awaitingFinishOrClientRedirect:
            // handle client (js) redirect
            return .client(delay: 0)

        case .expected, .responseReceived, .finished, .failed:
            // not expecting redirect
            return nil

        case .redirected:
            assertionFailure("unexpected state \(self.state), Navigation is already redirected")
            return nil
        }
    }

    mutating func redirected() {
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
        "<\(identity) #\(navigationAction.identifier): \(isSimulated == true ? "simulated " : "")url:\(url.absoluteString) state:\(state)\(isCommitted ? "(committed)" : "") type:\(navigationAction.navigationType)>"
    }
}

extension NavigationIdentity: CustomStringConvertible {
    public var description: String {
        guard var value else { return "nil" }
        if let autoResolved = value as? AutoresolvedValueBox {
            guard let resolved = autoResolved.value else {
                return "AUTO_NAVIG_ID_UNRESOLVED"
            }
            value = resolved
        }
        return type(of: value).description() + ":" + Unmanaged.passUnretained(value).toOpaque().debugDescription.replacing(regex: "^0x0*", with: "0x")
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
