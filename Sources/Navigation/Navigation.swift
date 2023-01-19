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

import Common
import Foundation
import WebKit

// swiftlint:disable line_length
public struct Navigation: Equatable {
    fileprivate(set) var identity: NavigationIdentity

    public private(set) var navigationAction: NavigationAction
    public private(set) var state: NavigationState
    public private(set) var isCommitted: Bool = false
    public private(set) var didReceiveAuthenticationChallenge: Bool = false

    public init(navigationAction: NavigationAction, state: NavigationState = .expected, identity: NavigationIdentity = .expected, isCommitted: Bool = false) {
        self.navigationAction = navigationAction
        self.state = state
        self.identity = identity
        self.isCommitted = isCommitted
    }

    static func expected(navigationAction: NavigationAction, redirectedNavigation: Navigation? = nil) -> Navigation {
        let identity: NavigationIdentity?
        switch navigationAction.navigationType {
        case .redirect(let redirect) where redirect.type.isClient:
            // new WKNavigation starts for js redirects
            identity = nil
        case .redirect:
            // the same WKNavigation is continued for server redirects
            identity = redirectedNavigation?.identity
        case .reload, .backForward, .formSubmitted, .formResubmitted, .linkActivated,
             .custom, .sessionRestoration, .other:
            // not a redirect navigation
            identity = nil
        }

        return Navigation(navigationAction: navigationAction, state: .expected, identity: identity ?? .expected)
    }

    static func started(navigationAction: NavigationAction, navigation wkNavigation: WKNavigation?) -> Navigation {
        var navigation = Navigation(navigationAction: navigationAction, state: .expected, identity: .expected)
        navigation.started(wkNavigation)
        return navigation
    }

    public var request: URLRequest {
        navigationAction.request
    }

    public var url: URL {
        navigationAction.url
    }

    public var redirectHistory: [RedirectHistoryItem]? {
        navigationAction.navigationType.redirect?.history
    }

    public static func == (lhs: Navigation, rhs: Navigation) -> Bool {
        lhs.identity == rhs.identity && lhs.navigationAction == rhs.navigationAction && lhs.state == rhs.state && lhs.isCommitted == rhs.isCommitted
    }

}

public enum NavigationState: Equatable {
    case expected
    case started

    case redirected

    case responseReceived(NavigationResponse)
    case finished
    case failed(WKError)

    public var isResponseReceived: Bool {
        if case .responseReceived = self { return true }
        return false
    }

    public var response: NavigationResponse? {
        if case .responseReceived(let response) = self { return response }
        return nil
    }

    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    public static func == (lhs: NavigationState, rhs: NavigationState) -> Bool {
        switch lhs {
        case .expected: if case .expected = rhs { return true }
        case .started: if case .started = rhs { return true }
        case .redirected: if case .redirected = rhs { return true }
        case .responseReceived(let resp): if case .responseReceived(resp) = rhs { return true }
        case .finished: if case .finished = rhs { return true }
        case .failed(let error1): if case .failed(let error2) = rhs { return error1.code == error2.code }
        }
        return false
    }

}

public struct NavigationIdentity: Equatable {

    private var value: AnyObject?

    public init(_ value: AnyObject?) {
        self.value = value
    }

    public static var expected = NavigationIdentity(nil)

    fileprivate mutating func resolve(with navigation: WKNavigation?) {
        assert(self.value == nil || self.value === navigation)
        self.value = navigation
    }

    public static func == (lhs: NavigationIdentity, rhs: NavigationIdentity) -> Bool {
        return lhs.value === rhs.value
    }

}

extension Navigation {

    mutating func started(_ navigation: WKNavigation?) {
        self.identity.resolve(with: navigation)

        guard case .expected = self.state else {
            assertionFailure("unexpected state \(self.state)")
            return
        }

        self.state = .started
    }

    mutating func challengeRececived() {
        self.didReceiveAuthenticationChallenge = true
    }

    mutating func committed(_ navigation: WKNavigation?) {
        self.identity.resolve(with: navigation)
        assert(state == .started || state.isResponseReceived)
        self.isCommitted = true
    }

    mutating func receivedResponse(_ response: NavigationResponse) {
        assert(state == .started)
        self.state = .responseReceived(response)
    }

    mutating func didFinish(_ navigation: WKNavigation?) {
        self.identity.resolve(with: navigation)

        switch self.state {
        case .started, .redirected:
            self.state = .finished
        case .responseReceived:
            // regular flow
            self.state = .finished
        case .expected, .finished, .failed:
            assertionFailure("unexpected state \(self.state)")
        }
    }

    mutating func didFail(_ navigation: WKNavigation? = nil, with error: WKError) {
        assert(state != .expected, "non-started navigations should‘t receive didFail")
        if let navigation {
            self.identity.resolve(with: navigation)
        }
        self.state = .failed(error)
    }

    mutating func didReceiveServerRedirect(for navigation: WKNavigation?) {
        assert(state == .expected || state == .started, "didReceiveServerRedirect should happen after decidePolicyForNavigationAction")
        self.identity.resolve(with: navigation)
        self.state = .started
    }

    mutating func redirected() {
        switch state {
        case  .started:
            self.state = .redirected
        case .expected, .responseReceived, .finished, .failed, .redirected:
            assertionFailure("unexpected state \(self.state)")
        }
    }

}

extension Navigation: CustomDebugStringConvertible {
    public var debugDescription: String {
        "<\(identity) #\(navigationAction.identifier): url:\(url.absoluteString) state:\(state)\(isCommitted ? "(committed)" : "") type:\(navigationAction.navigationType)>"
    }
}

extension NavigationIdentity: CustomStringConvertible {
    public var description: String {
        guard let value else { return "nil" }
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
