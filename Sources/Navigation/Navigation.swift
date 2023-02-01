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
@MainActor
public final class Navigation {

    fileprivate(set) var identity: NavigationIdentity

    internal private(set) var navigationActions = [NavigationAction]()
    public var navigationResponders: ResponderChain

    /// Is the navigation currently loaded in the WebView
    private(set) public var isCurrent: Bool

    public fileprivate(set) var state: NavigationState
    public private(set) var isCommitted: Bool = false
    public private(set) var didReceiveAuthenticationChallenge: Bool = false

    /// Currently performed Navigation Action. May change for server redirects.
    public var navigationAction: NavigationAction {
        // should always have at least one NavigationAction after `navigationActionReceived` or `started`
        navigationActions.last!
    }
    /// Previous Navigation Actions received during current logical `Navigation`, zero-based, most recent is the last
    public var redirectHistory: [NavigationAction] {
        Array(navigationActions.dropLast())
    }
    public private(set) var navigationResponse: NavigationResponse?

    init(identity: NavigationIdentity, responders: ResponderChain, state: NavigationState, isCurrent: Bool, isCommitted: Bool = false) {
        self.state = state
        self.identity = identity
        self.isCommitted = isCommitted
        self.navigationResponders = responders
        self.isCurrent = isCurrent
    }

    public var request: URLRequest {
        guard !navigationActions.isEmpty else { return URLRequest(url: .empty) }
        return navigationAction.request
    }

    public var url: URL {
        request.url ?? .empty
    }

    public var isCompleted: Bool {
        return state.isFinished || state.isFailed
    }

}

public protocol NavigationProtocol: AnyObject {
    var navigationResponders: ResponderChain { get set }
}

extension Navigation: NavigationProtocol {}

@MainActor
public extension NavigationProtocol {

    /** override responder chain for Navigation Events with defined ownership and nullability:
     ```
     navigation.overrideResponders( .weak(responder1), .weak(nullable: responder2), .strong(responder3), .strong(nullable: responder4))
     ```
     **/
    func overrideResponders(_ refs: ResponderRefMaker?...) {
        dispatchPrecondition(condition: .onQueue(.main))

        navigationResponders.setResponders(refs.compactMap { $0 })
    }

    @discardableResult
    func overridingResponders(with decidePolicy: ((_: NavigationAction, _: inout NavigationPreferences) async -> NavigationActionPolicy?)? = nil,
                              willStart: ((_: Navigation) -> Void)? = nil,
                              didStart: ((_: Navigation) -> Void)? = nil,
                              authenticationChallenge: ((_: URLAuthenticationChallenge, Navigation?) async -> AuthChallengeDisposition?)? = nil,
                              redirected: ((_: NavigationAction, Navigation) -> Void)? = nil,
                              navigationResponse: ((NavigationResponse) async -> NavigationResponsePolicy?)? = nil,
                              didCommit: ((Navigation) -> Void)? = nil,
                              navigationDidFinish: ((Navigation) -> Void)? = nil,
                              navigationDidFail: ((Navigation, WKError, _: Bool) -> Void)? = nil,
                              navigationActionWillBecomeDownload: ((NavigationAction, WKWebView) -> Void)? = nil,
                              navigationActionDidBecomeDownload: ((NavigationAction, WebKitDownload) -> Void)? = nil,
                              navigationResponseWillBecomeDownload: ((NavigationResponse, WKWebView) -> Void)? = nil,
                              navigationResponseDidBecomeDownload: ((NavigationResponse, WebKitDownload) -> Void)? = nil) -> Self {
        self.overrideResponders(.struct(ClosureNavigationResponder(decidePolicy: decidePolicy, willStart: willStart, didStart: didStart, authenticationChallenge: authenticationChallenge, redirected: redirected, navigationResponse: navigationResponse, didCommit: didCommit, navigationDidFinish: navigationDidFinish, navigationDidFail: navigationDidFail, navigationActionWillBecomeDownload: navigationActionWillBecomeDownload, navigationActionDidBecomeDownload: navigationActionDidBecomeDownload, navigationResponseWillBecomeDownload: navigationResponseWillBecomeDownload, navigationResponseDidBecomeDownload: navigationResponseDidBecomeDownload)))
        return self
    }

    @discardableResult
    func appendingResponder(with decidePolicy: ((_: NavigationAction, _: inout NavigationPreferences) async -> NavigationActionPolicy?)? = nil,
                            willStart: ((_: Navigation) -> Void)? = nil,
                            didStart: ((_: Navigation) -> Void)? = nil,
                            authenticationChallenge: ((_: URLAuthenticationChallenge, Navigation?) async -> AuthChallengeDisposition?)? = nil,
                            redirected: ((_: NavigationAction, Navigation) -> Void)? = nil,
                            navigationResponse: ((NavigationResponse) async -> NavigationResponsePolicy?)? = nil,
                            didCommit: ((Navigation) -> Void)? = nil,
                            navigationDidFinish: ((Navigation) -> Void)? = nil,
                            navigationDidFail: ((Navigation, WKError, _: Bool) -> Void)? = nil,
                            navigationActionWillBecomeDownload: ((NavigationAction, WKWebView) -> Void)? = nil,
                            navigationActionDidBecomeDownload: ((NavigationAction, WebKitDownload) -> Void)? = nil,
                            navigationResponseWillBecomeDownload: ((NavigationResponse, WKWebView) -> Void)? = nil,
                            navigationResponseDidBecomeDownload: ((NavigationResponse, WebKitDownload) -> Void)? = nil) -> Self {
        self.navigationResponders.append(.struct(ClosureNavigationResponder(decidePolicy: decidePolicy, willStart: willStart, didStart: didStart, authenticationChallenge: authenticationChallenge, redirected: redirected, navigationResponse: navigationResponse, didCommit: didCommit, navigationDidFinish: navigationDidFinish, navigationDidFail: navigationDidFail, navigationActionWillBecomeDownload: navigationActionWillBecomeDownload, navigationActionDidBecomeDownload: navigationActionDidBecomeDownload, navigationResponseWillBecomeDownload: navigationResponseWillBecomeDownload, navigationResponseDidBecomeDownload: navigationResponseDidBecomeDownload)))
        return self
    }

}

public enum NavigationState: Equatable {

    case expected(NavigationType?)
    case navigationActionReceived
    case started

    case willPerformClientRedirect(delay: TimeInterval)
    case redirected(RedirectType)

    case responseReceived
    case finished
    case failed(WKError)

    public var isExpected: Bool {
        if case .expected = self { return true }
        return false
    }

    var expectedNavigationType: NavigationType? {
        if case .expected(let navigationType) = self { return navigationType }
        return nil
    }

    public var isResponseReceived: Bool {
        if case .responseReceived = self { return true }
        return false
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
        case .expected(let navigationType): if case .expected(navigationType) = rhs { return true }
        case .navigationActionReceived: if case .navigationActionReceived = rhs { return true }
        case .started: if case .started = rhs { return true }
        case .willPerformClientRedirect(delay: let delay): if case .willPerformClientRedirect(delay: delay) = rhs { return true }
        case .redirected(let type): if case .redirected(type) = rhs { return true }
        case .responseReceived: if case .responseReceived = rhs { return true }
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

    func associate(with wkNavigation: WKNavigation?) {
        guard let wkNavigation, wkNavigation.navigation == nil else { return }

        // ensure Navigation object lifetime is bound to the WKNavigation in case it‘s not properly started or finished
        WKNavigationLifetimeTracker(navigation: self).bind(to: wkNavigation)
        wkNavigation.navigation = self
    }

    private func resolve(with wkNavigation: WKNavigation?) {
        self.associate(with: wkNavigation)
        self.identity.resolve(with: wkNavigation)
    }

    func navigationActionReceived(_ navigationAction: NavigationAction) {
        assert(navigationAction.isForMainFrame)

        switch state {
        case .expected(let navigationType):
            // new navigations
            assert(navigationType == nil || navigationType == navigationAction.navigationType)
            let navigationActions = (navigationAction.redirectHistory ?? []) + [navigationAction]
            if self.navigationActions.isEmpty {
                self.navigationActions = navigationActions
            } else {
                // replace empty NavigationAction with expectedNavigationType with the actual NavigationAction
                _=self.navigationActions.removeLast()
                self.navigationActions.append(contentsOf: navigationActions)
            }
            self.state = .navigationActionReceived

        case .started:
            willPerformServerRedirect(with: navigationAction)

        case .navigationActionReceived, .responseReceived, .finished, .failed, .willPerformClientRedirect, .redirected:
            assertionFailure("unexpected state \(self.state)")
        }
    }

    func started(_ navigation: WKNavigation?) {
        self.resolve(with: navigation)

        guard case .navigationActionReceived = self.state else {
            assertionFailure("unexpected state \(self.state)")
            return
        }

        self.state = .started
        isCurrent = true
    }

    func didResignCurrent() {
        guard isCurrent else { return }
        isCurrent = false
    }

    func challengeRececived() {
        self.didReceiveAuthenticationChallenge = true
    }

    func committed(_ navigation: WKNavigation?) {
        self.resolve(with: navigation)
        assert(state == .started || state.isResponseReceived)
        self.isCommitted = true
    }

    func receivedResponse(_ response: NavigationResponse) {
        assert(state == .started)
        self.navigationResponse = response
        self.state = .responseReceived
    }

    func didFinish(_ navigation: WKNavigation?) {
        self.resolve(with: navigation)

        switch self.state {
        case .willPerformClientRedirect:
            // expecting didPerformClientRedirect/didCancelClientRedirect/didFail
            return
        case .started, .redirected:
            self.state = .finished
        case .responseReceived:
            // regular flow
            self.state = .finished
        case .expected, .navigationActionReceived, .finished, .failed:
            assertionFailure("unexpected state \(self.state)")
        }
        isCurrent = false
    }

    func didFail(_ navigation: WKNavigation? = nil, with error: WKError) {
        assert(!state.isExpected, "non-started navigations should‘t receive didFail")
        if let navigation {
            self.resolve(with: navigation)
        }
        self.state = .failed(error)
        isCurrent = false
    }

    func willPerformServerRedirect(with navigationAction: NavigationAction) {
        assert(navigationAction.navigationType == .redirect(.server))

        switch state {
        case .started:
            self.state = .redirected(.server)
            self.navigationActions.append(navigationAction)
        case .expected, .navigationActionReceived, .responseReceived, .finished, .failed, .willPerformClientRedirect, .redirected:
            assertionFailure("unexpected state \(self.state)")
        }
    }

    func didReceiveServerRedirect(for navigation: WKNavigation?) {
        self.resolve(with: navigation)
        switch state {
        case .redirected(.server):
            // expected didReceiveServerRedirect
            self.state = .started
        case .started:
            // duplicate(cyclic) server redirect called without decidePolicyForNavigationAction:
            self.navigationActions.append(self.navigationActions.last!)
        case .expected, .navigationActionReceived, .failed, .finished, .responseReceived, .willPerformClientRedirect, .redirected:
            assertionFailure("didReceiveServerRedirect should happen after decidePolicyForNavigationAction")
        }
    }

    func willPerformClientRedirect(to url: URL, delay: TimeInterval) {
        switch state {
        case .started, .responseReceived:
            self.state = .willPerformClientRedirect(delay: delay)
        case .expected, .navigationActionReceived, .finished, .failed, .willPerformClientRedirect, .redirected:
            assertionFailure("unexpected state \(self.state)")
        }
    }

    func didPerformClientRedirect(with navigationAction: NavigationAction) {
        guard case .willPerformClientRedirect(delay: let delay) = state else {
            assertionFailure("unexpected didPerformClientRedirect")
            return
        }

        self.state = .redirected(.client(delay: delay))
        for responder in navigationResponders {
            responder.didReceiveRedirect(navigationAction, for: self)
        }
    }

    func didSendDidPerformClientRedirectToResponders() {
        guard case .redirected(.client) = state else {
            assertionFailure("unexpected didPerformClientRedirect")
            return
        }
        self.state = .finished
        self.isCurrent = false
    }

    func didCancelClientRedirect() {
        guard case .redirected(.client) = state else {
            assertionFailure("unexpected didPerformClientRedirect")
            return
        }
        self.state = .started
        self.isCurrent = false
    }

}

// ensures Navigation object lifetime is bound to the WKNavigation in case it‘s not properly started or finished
@MainActor
final class WKNavigationLifetimeTracker: NSObject {
    private let navigation: Navigation
    private static let wkNavigationLifetimeKey = UnsafeRawPointer(bitPattern: "wkNavigationLifetimeKey".hashValue)!

    init(navigation: Navigation) {
        self.navigation = navigation
    }

    func bind(to wkNavigation: NSObject) {
        objc_setAssociatedObject(wkNavigation, Self.wkNavigationLifetimeKey, self, .OBJC_ASSOCIATION_RETAIN)
    }

    private static func checkNavigationCompletion(_ navigation: Navigation) {
        guard !navigation.isCompleted else { return }

        let error = WKError(_nsError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
        navigation.state = .failed(error)

        for responder in navigation.navigationResponders {
            responder.navigation(navigation, didFailWith: error, isProvisional: navigation.isCommitted)
        }
    }

    deinit {
        DispatchQueue.main.async { [navigation] in
            Self.checkNavigationCompletion(navigation)
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
        "WKNavigation: " + (value?.pointerValue?.debugDescription.replacing(regex: "^0x0*", with: "0x") ?? "nil")
    }
}

extension NavigationState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .expected(let navigationType): return "expected(\(navigationType?.debugDescription ?? ""))"
        case .navigationActionReceived: return "navigationActionReceived"
        case .started: return "started"
        case .willPerformClientRedirect: return "willPerformClientRedirect"
        case .redirected: return "redirected"
        case .responseReceived: return "responseReceived"
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
