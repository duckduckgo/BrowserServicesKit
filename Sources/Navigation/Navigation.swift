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

import Combine
import Common
import Foundation
import WebKit

// swiftlint:disable line_length
public final class Navigation {

    fileprivate(set) var identity: NavigationIdentity

    internal private(set) var navigationActions: [NavigationAction]

    @Published public fileprivate(set) var state: NavigationState
    @Published public private(set) var isCommitted: Bool = false
    @Published public private(set) var didReceiveAuthenticationChallenge: Bool = false

    /// Currently performed Navigation Action. May change for server redirects.
    public var navigationAction: NavigationAction {
        navigationActions.last!
    }
    /// Previous Navigation Actions received during current logical `Navigation`, zero-based, most recent is the last
    public var redirectHistory: [NavigationAction] {
        Array(navigationActions.dropLast())
    }

    public init(navigationAction: NavigationAction, state: NavigationState = .expected, identity: NavigationIdentity = .expected, isCommitted: Bool = false) {
        self.navigationActions = (navigationAction.redirectHistory ?? []) + [navigationAction]
        self.state = state
        self.identity = identity
        self.isCommitted = isCommitted
    }

    static func expected(navigationAction: NavigationAction, identity expectedIdentity: NavigationIdentity) -> Navigation {
        let identity: NavigationIdentity
        switch navigationAction.navigationType {
        case .redirect(.client), .redirect(.developer):
            // new WKNavigation starts for js redirects
            identity = expectedIdentity
        case .redirect(.server):
            // the same WKNavigation is continued for server redirects
            assertionFailure("should not create new Navigation for redirects")
            identity = expectedIdentity
        case .reload, .backForward, .formSubmitted, .formResubmitted, .linkActivated,
             .custom, .sessionRestoration, .other:
            // not a redirect navigation
            identity = expectedIdentity
        }

        return Navigation(navigationAction: navigationAction, state: .expected, identity: identity)
    }

    static func started(navigationAction: NavigationAction, navigation wkNavigation: WKNavigation?) -> Navigation {
        let navigation = Navigation(navigationAction: navigationAction, state: .expected, identity: .expected)
        navigation.started(wkNavigation)
        return navigation
    }

    public var request: URLRequest {
        navigationAction.request
    }

    public var url: URL {
        navigationAction.url
    }

    public var isCompleted: Bool {
        return state.isFinished || state.isFailed
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

    public var isFinished: Bool {
        if case .finished = self { return true }
        return false
    }

    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    // swiftlint:disable:next cyclomatic_complexity
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

    private var value: NSValue?

    public init(_ value: AnyObject?) {
        self.value = value.map(NSValue.init(nonretainedObject:))
    }

    public static var expected = NavigationIdentity(nil)

    fileprivate mutating func resolve(with navigation: WKNavigation?) {
        guard let navigation else { return }
        let newValue = NSValue(nonretainedObject: navigation)
        assert(self.value == nil || self.value == newValue)
        self.value = newValue
    }

    public static func == (lhs: NavigationIdentity, rhs: NavigationIdentity) -> Bool {
        return lhs.value == rhs.value
    }

}

extension Navigation {

    func started(_ navigation: WKNavigation?) {
        self.identity.resolve(with: navigation)

        guard case .expected = self.state else {
            assertionFailure("unexpected state \(self.state)")
            return
        }

        self.state = .started
    }

    func challengeRececived() {
        self.didReceiveAuthenticationChallenge = true
    }

    func committed(_ navigation: WKNavigation?) {
        self.identity.resolve(with: navigation)
        assert(state == .started || state.isResponseReceived)
        self.isCommitted = true
    }

    func receivedResponse(_ response: NavigationResponse) {
        assert(state == .started)
        self.state = .responseReceived(response)
    }

    func didFinish(_ navigation: WKNavigation?) {
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

    func didFail(_ navigation: WKNavigation? = nil, with error: WKError) {
        assert(state != .expected, "non-started navigations should‘t receive didFail")
        if let navigation {
            self.identity.resolve(with: navigation)
        }
        self.state = .failed(error)
    }

    func didReceiveServerRedirect(for navigation: WKNavigation?) {
        self.identity.resolve(with: navigation)
        switch state {
        case .redirected:
            // expected didReceiveServerRedirect
            self.state = .started
        case .started:
            // duplicate(cyclic) server redirect called without decidePolicyForNavigationAction:
            self.navigationActions.append(self.navigationActions.last!)
        case .expected, .failed, .finished, .responseReceived:
            assertionFailure("didReceiveServerRedirect should happen after decidePolicyForNavigationAction")
        }
    }

    func redirected(with navigationAction: NavigationAction) {
        switch state {
        case .started:
            self.state = .redirected
            self.navigationActions.append(navigationAction)
        case .expected, .responseReceived, .finished, .failed, .redirected:
            assertionFailure("unexpected state \(self.state)")
        }
    }

}

// ensures Navigation object lifetime is bound to the WKNavigation in case it‘s not properly started or finished
final class WKNavigationLifetimeTracker: NSObject {
    private let navigation: Navigation
    private static let wkNavigationLifetimeKey = UnsafeRawPointer(bitPattern: "wkNavigationLifetimeKey".hashValue)!

    init(navigation: Navigation) {
        self.navigation = navigation
    }

    func bind(to wkNavigation: NSObject) {
        objc_setAssociatedObject(wkNavigation, Self.wkNavigationLifetimeKey, self, .OBJC_ASSOCIATION_RETAIN)
    }

    deinit {
        guard !navigation.isCompleted else { return }
        navigation.state = .failed(WKError(_nsError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
    }

}

extension Navigation: CustomDebugStringConvertible {
    public var debugDescription: String {
        "<\(identity) #\(navigationAction.identifier): url:\(url.absoluteString) state:\(state)\(isCommitted ? "(committed)" : "") type:\(navigationAction.navigationType)>"
    }
}

extension NavigationIdentity: CustomStringConvertible {
    public var description: String {
        "WKNavigation: " + (value?.pointerValue?.debugDescription.replacing(regex: "^0x0*", with: "0x") ?? "nil")
    }
}

extension NavigationState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .expected: return "expected"
        case .started: return "started"
        case .redirected: return "redirected"
        case .responseReceived(let response): return "responseReceived(\(response.debugDescription))"
        case .finished: return "finished"
        case .failed(let error): return "failed(\(error.errorDescription ?? error.localizedDescription))"
        }
    }
}

extension RedirectType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .client(delay: let delay): return "client" + (delay > 0 ? "(delay: \(delay))" : "")
        case .server: return "server"
        case .developer: return "developer"
        }
    }
}
