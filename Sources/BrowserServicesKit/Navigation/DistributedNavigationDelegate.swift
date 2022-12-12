//
//  DistributedNavigationDelegate.swift
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
import os.log
import WebKit

// swiftlint:disable file_length
// swiftlint:disable line_length
public final class DistributedNavigationDelegate: NSObject {

    private var responderRefs: [AnyResponderRef] = []
    private var customDelegateMethodHandlers = [Selector: AnyResponderRef]()
    private let logger: OSLog

    /// developer defined (or set after js-redirect) mapping to an expected WKNavigationAction. May incude custom NavigationTypes defined using UserInfo
    public private(set) var expectedNavigationAction: (navigationType: NavigationType?, condition: NavigationMatchingCondition?)?
    /// sets developer-defined NavigationType for a next expected WKNavigationAction
    public func setExpectedNavigationType(_ navigationType: NavigationType, matching condition: NavigationMatchingCondition? = .none /*any*/) {
        expectedNavigationAction = (navigationType, condition)
    }

    /// approved navigation before `navigationDidStart` event received
    private var navigationExpectedToStart: Navigation? {
        didSet {
            updateCurrentNavigation()
        }
    }
    /// ongoing Main Frame navigation (after `navigationDidStart` event received)
    private var startedNavigation: Navigation? {
        didSet {
            updateCurrentNavigation()
        }
    }

    /// published "current" navigation - represents either started or approved (expected to start) navigation
    @Published public private(set) var currentNavigation: Navigation?
    private func updateCurrentNavigation() {
        let currentNavigation = startedNavigation ?? navigationExpectedToStart
        guard self.currentNavigation != currentNavigation else { return }
        self.currentNavigation = currentNavigation
    }

    /// last BackForwardList item committed into WebView
    public private(set) var currentHistoryItemIdentity: HistoryItemIdentity?

    public init(logger: OSLog) {
        self.logger = logger
    }

    /** set responder chain for Navigation Events with defined ownership and nullability:
     ```
     navigationDelegate.setResponders( .weak(responder1), .weak(nullable: responder2), .strong(responder3), .strong(nullable: responder4))
     ```
     **/
    public func setResponders(_ refs: ResponderRefMaker?...) {
        let nonnullRefs = refs.compactMap { $0 }
        responderRefs = nonnullRefs.map(\.ref)
        assert(responders.count == nonnullRefs.count, "Some NavigationResponders were released right after adding: "
               + "\(Set(nonnullRefs.map(\.ref.responderType)).subtracting(responders.map { "\(type(of: $0))" }))")
    }

}

public enum NavigationMatchingCondition: Equatable {
    case url(URL)
    case navigationType(WKNavigationType)
    case both(navigationType: WKNavigationType, url: URL)

    func matches(_ navigationAction: WKNavigationAction) -> Bool {
        switch self {
        case .url(let url):
            return navigationAction.request.url?.matches(url) == true
        case .navigationType(let navigationType):
            return navigationAction.navigationType == navigationType
        case .both(navigationType: let navigationType, url: let url):
            return navigationAction.navigationType == navigationType && navigationAction.request.url?.matches(url) == true
        }
    }
}

private extension DistributedNavigationDelegate {

    /// continues until first non-nil Navigation Responder decision and returned to the `completion` callback
    func makeAsyncDecision<T>(decide: @escaping (NavigationResponder) async -> T?,
                              completion: @escaping (T?) -> Void) {
        Task { @MainActor in
            var result: T?
            for responder in responders {
                guard let decision = await decide(responder) else { continue }
                result = decision
                break
            }
            completion(result)
        }
    }

    /// Maps `WKNavigationAction` to `NavigationAction` according to an active server redirect or an expected NavigationType
    func navigationAction(for navigationAction: WKNavigationAction, in webView: WKWebView) -> NavigationAction {
        guard navigationAction.targetFrame?.isMainFrame == true else {
            return NavigationAction(webView: webView, navigationAction: navigationAction, currentHistoryItemIdentity: currentHistoryItemIdentity)
        }

        let navigationType: NavigationType?
        if let expected = expectedNavigationAction,
           expected.condition?.matches(navigationAction) ?? true {
            // client-defined or client-redirect expected navigation type matching current main frame navigation URL
            navigationType = expected.navigationType
            // ! don‘t nullify the expectedNavigationAction until the decision is taken

        } else if var startedNavigation, case .started = startedNavigation.state {
            // received server redirect
            navigationType = .redirect(Redirect(type: .server, appending: startedNavigation, to: startedNavigation.navigationAction.navigationType.redirect))
            startedNavigation.redirected()
            self.startedNavigation = startedNavigation

        } else {
            navigationType = nil // resolve from WKNavigationAction navigation type
        }

        return NavigationAction(webView: webView, navigationAction: navigationAction, currentHistoryItemIdentity: currentHistoryItemIdentity, navigationType: navigationType)
    }

}

// MARK: - WKNavigationDelegate
extension DistributedNavigationDelegate: WKNavigationDelegate {

    // MARK: Policy making

    @MainActor
    public func webView(_ webView: WKWebView, decidePolicyFor wkNavigationAction: WKNavigationAction, preferences wkPreferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        let navigationAction = navigationAction(for: wkNavigationAction, in: webView)
        os_log("decidePolicyFor: %s", log: logger, type: .default, navigationAction.debugDescription)

        var preferences = NavigationPreferences(userAgent: webView.customUserAgent, preferences: wkPreferences)
        makeAsyncDecision { responder in
            dispatchPrecondition(condition: .onQueue(.main))

            guard !Task.isCancelled else {
                os_log("cancelling %s because of Task cancellation", log: self.logger, type: .default, navigationAction.debugDescription)
                return .cancel(with: .taskCancelled)
            }
            guard let decision = await responder.decidePolicy(for: navigationAction, preferences: &preferences) else { return .next }
            os_log("%s: %s decision: %s", log: self.logger, type: .default, navigationAction.debugDescription, "\(type(of: responder))", decision.debugDescription)

            return decision

        } completion: { (decision: NavigationActionPolicy?) in
            dispatchPrecondition(condition: .onQueue(.main))
            if self.expectedNavigationAction?.navigationType == navigationAction.navigationType && self.expectedNavigationAction?.condition?.matches(wkNavigationAction) == true {
                self.expectedNavigationAction = nil // reset
            }

            switch decision {
            case .allow, .none:
                webView.customUserAgent = preferences.userAgent
                decisionHandler(.allow, preferences.applying(to: wkPreferences))
                self.willStart(navigationAction)

            case .cancel(let relatedAction):
                self.willCancel(navigationAction, with: relatedAction)
                decisionHandler(.cancel, wkPreferences)
                self.didCancel(navigationAction, with: relatedAction)

            case .download:
                decisionHandler(.download, wkPreferences)
            }
        }
    }

    @MainActor
    private func willStart(_ navigationAction: NavigationAction) {
        guard navigationAction.isForMainFrame else { return }
        os_log("willStart %s", log: logger, type: .default, navigationAction.debugDescription)

        var redirectedNavigation: Navigation?
        if let startedNavigation {
            switch startedNavigation.state {
            case .redirected:
                redirectedNavigation = startedNavigation
            case .started, .responseReceived:
                // current navigation still didn‘t receive didFinish or didFail event yet
                // further operations (didReceiveAuthenticationChallenge, didReceiveServerRedirect, didStart)
                // should use `navigationExpectedToStart`, let the `startedNavigation` finish
                break
            case .expected:
                assertionFailure("dropping previous expectated navigation: \(startedNavigation.navigationAction.debugDescription)")
            case .finished, .failed:
                assertionFailure("finished navigation should be nil")
            }
        }

        if let redirectedNavigation {
            // overwrite startedNavigation for redirected navigation
            startedNavigation = .expected(navigationAction: navigationAction, redirectedNavigation: redirectedNavigation)
            navigationExpectedToStart = nil
        } else {
            navigationExpectedToStart = .expected(navigationAction: navigationAction)
        }

        for responder in responders {
            responder.willStart(navigationAction)
        }
    }

    @MainActor
    private func willCancel(_ navigationAction: NavigationAction, with relatedAction: NavigationActionCancellationRelatedAction) {
        guard navigationAction.isForMainFrame else { return }
        os_log("willCancel %s with %s", log: logger, type: .default, navigationAction.debugDescription, relatedAction.debugDescription)

        for responder in responders {
            responder.willCancel(navigationAction, with: relatedAction)
        }
    }

    @MainActor
    private func didCancel(_ navigationAction: NavigationAction, with relatedAction: NavigationActionCancellationRelatedAction) {
        guard navigationAction.isForMainFrame else { return }
        os_log("didCancel %s with %s", log: logger, type: .default, navigationAction.debugDescription, relatedAction.debugDescription)

        for responder in responders {
            responder.didCancel(navigationAction, with: relatedAction)
        }
    }

    // MARK: Pre-Navigation

    @MainActor
    public func webView(_ webView: WKWebView,
                        didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // previous navigation may stil be expecting completion at this point
        var navigation = navigationExpectedToStart ?? startedNavigation
        navigation?.challengeRececived()
        if navigationExpectedToStart != nil {
            navigationExpectedToStart = navigation
        } else {
            startedNavigation = navigation
        }
        os_log("didReceive challenge: %s: %s", log: logger, type: .default, navigation?.debugDescription ?? webView.debugDescription, String(describing: challenge))

        makeAsyncDecision { responder in
            guard let decision = await responder.didReceive(challenge, for: navigation) else { return .next }
            os_log("%s: %s decision: %s", log: self.logger, type: .default, String(describing: challenge), "\(type(of: responder))", String(describing: decision.dispositionAndCredential.0/*disposition*/))

            return decision

        } completion: { (decision: AuthChallengeDisposition?) in
            guard let (disposition, credential) = decision?.dispositionAndCredential else {
                os_log("%s: performDefaultHandling", log: self.logger, type: .default, String(describing: challenge))
                completionHandler(.performDefaultHandling, nil)
                return
            }
            completionHandler(disposition, credential)
        }
    }

    @MainActor
    public func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation wkNavigation: WKNavigation?) {
        // previous navigation may stil be expecting completion at this point
        guard var navigation = navigationExpectedToStart ?? startedNavigation else {
            assertionFailure("No navigation is expected to receive server redirect")
            return
        }

        navigation.didReceiveServerRedirect(for: wkNavigation)
        os_log("didReceiveServerRedirect for: %s", log: logger, type: .default, navigation.debugDescription)

        if self.navigationExpectedToStart != nil {
            self.navigationExpectedToStart = navigation
        } else {
            self.startedNavigation = navigation
        }
    }

    // MARK: Navigation

    @MainActor
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation wkNavigation: WKNavigation?) {
        let navigation: Navigation
        if var expectedNavigation = navigationExpectedToStart, let wkNavigation {
            // regular flow: start .expected navigation
            expectedNavigation.started(wkNavigation)
            navigation = expectedNavigation

        } else {
            // session restoration happens without NavigationAction
            navigation = .started(navigationAction: .sessionRestoreNavigation(webView: webView), navigation: wkNavigation)
        }
        startedNavigation = navigation
        navigationExpectedToStart = nil

        os_log("didStart: %s", log: logger, type: .default, navigation.debugDescription)
        assert(navigation.navigationAction.navigationType.redirect?.type != .server, "server redirects shouldn‘t call didStartProvisionalNavigation")

        for responder in responders {
            responder.didStart(navigation)
        }
    }

    @MainActor
    public func webView(_ webView: WKWebView, decidePolicyFor wkNavigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let navigationResponse = NavigationResponse(navigationResponse: wkNavigationResponse)
        if wkNavigationResponse.isForMainFrame {
            assert(startedNavigation != nil)
            startedNavigation?.receivedResponse(navigationResponse)
        }

        os_log("decidePolicyFor response: %s current: %s", log: logger, type: .default, navigationResponse.debugDescription, startedNavigation?.debugDescription ?? "<nil>")

        makeAsyncDecision { [startedNavigation] responder in
            guard let decision = await responder.decidePolicy(for: navigationResponse, currentNavigation: startedNavigation) else { return .next }
            os_log("%s: %s decision: %s", log: self.logger, type: .default, navigationResponse.debugDescription, "\(type(of: responder))", "\(decision)")

            return decision

        } completion: { (decision: NavigationResponsePolicy?) in
            switch decision {
            case .allow, .none:
                decisionHandler(.allow)
            case .cancel:
                decisionHandler(.cancel)
            case .download:
                decisionHandler(.download)
            }
        }
    }

    @MainActor
    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) {
        startedNavigation?.committed(navigation)
        currentHistoryItemIdentity = webView.backForwardList.currentItem.map(HistoryItemIdentity.init)
        guard let startedNavigation else {
            assertionFailure("Unexpected didCommitNavigation")
            return
        }
        os_log("didCommit: %s", log: logger, type: .default, startedNavigation.debugDescription)

        for responder in responders {
            responder.didCommit(startedNavigation)
        }
    }

#if WILLPERFORMCLIENTREDIRECT_ENABLED
    @MainActor
    @objc(_webView:willPerformClientRedirectToURL:delay:)
    public func webView(_ webView: WKWebView, willPerformClientRedirectTo url: URL, delay: TimeInterval) {
        // ignore default implementation if method overriding done using registerCustomDelegateMethodHandler(for:selector)
        if let forwardingTarget = forwardingTarget(for: #selector(webView(_:willPerformClientRedirectTo:delay:))) {
            withUnsafePointer(to: forwardingTarget) { $0.withMemoryRebound(to: DistributedNavigationDelegate?.self, capacity: 1) { $0 } }.pointee!
                .webView(webView, willPerformClientRedirectTo: url, delay: delay)
            return
        }

        os_log("willPerformClientRedirect to: %s, current: %s", log: logger, type: .default, url.absoluteString, startedNavigation?.debugDescription ?? "<nil>")
        guard let startedNavigation else { return }
        if expectedNavigationAction?.condition != .url(url) {
            setExpectedNavigationType(.redirect(Redirect(type: .client(delay: delay),
                                                         appending: startedNavigation,
                                                         to: startedNavigation.navigationAction.navigationType.redirect)),
                                      matching: .url(url))
        }
    }

    @objc(_webViewDidCancelClientRedirect:)
    func webViewDidCancelClientRedirect(_ webView: WKWebView) {
        if expectedNavigationAction?.navigationType?.redirect?.type.isClient == true {
            expectedNavigationAction = nil
        }
    }
#endif

    // MARK: Completion

    @MainActor
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        startedNavigation?.didFinish(navigation)
        guard let startedNavigation = startedNavigation else {
            assertionFailure("Unexpected didFinishNavigation")
            return
        }
        os_log("didFinish: %s", log: logger, type: .default, startedNavigation.debugDescription)

        for responder in responders {
            responder.navigationDidFinish(startedNavigation)
        }

        self.startedNavigation = nil
    }

    @MainActor
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        let error = error as? WKError ?? WKError(_nsError: error as NSError)
        startedNavigation?.didFail(navigation, with: error)

        guard let startedNavigation else {
            assertionFailure("Unexpected navigationDidFail")
            return
        }
        os_log("didFail %s: %s", log: logger, type: .default, startedNavigation.debugDescription, error.localizedDescription)

        for responder in responders {
            responder.navigation(startedNavigation, didFailWith: error, isProvisioned: false)
        }
        self.startedNavigation = nil
    }

    @MainActor
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
        let error = error as? WKError ?? WKError(_nsError: error as NSError)
        startedNavigation?.didFail(navigation, with: error)

        guard let startedNavigation else {
            assertionFailure("Unexpected navigationDidFail")
            return
        }
        os_log("didFail provisional %s: %s", log: logger, type: .default, startedNavigation.debugDescription, error.localizedDescription)

        for responder in responders {
            responder.navigation(startedNavigation, didFailWith: error, isProvisioned: true)
        }
        self.startedNavigation = nil
    }

    @MainActor
    @available(macOS 11.3, iOS 14.5, *) // objc does‘t care about availability
    @objc(webView:navigationAction:didBecomeDownload:)
    public func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        let navigationAction = NavigationAction(webView: webView, navigationAction: navigationAction, currentHistoryItemIdentity: currentHistoryItemIdentity)
        for responder in responders {
            responder.navigationAction(navigationAction, didBecome: download)
        }
    }

    @MainActor
    @available(macOS 11.3, iOS 14.5, *) // objc does‘t care about availability
    @objc(webView:navigationResponse:didBecomeDownload:)
    public func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        let navigationResponse = NavigationResponse(navigationResponse: navigationResponse)
        for responder in responders {
            responder.navigationResponse(navigationResponse, didBecome: download, currentNavigation: startedNavigation)
        }
        if navigationResponse.isForMainFrame {
            startedNavigation = nil
        }
    }

    @MainActor
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        startedNavigation?.didFail(with: WKError(WKError.Code.webContentProcessTerminated))
        os_log("%s process did terminate; current navigation: %s", log: logger, type: .default, webView.debugDescription, startedNavigation?.debugDescription ?? "<nil>")

        for responder in responders {
            responder.webContentProcessDidTerminate(currentNavigation: startedNavigation)
        }
        startedNavigation = nil
        navigationExpectedToStart = nil
        expectedNavigationAction = nil
    }

}

// MARK: - Responders
extension DistributedNavigationDelegate {

    fileprivate enum ResponderRef: AnyResponderRef {
        case weak(ref: WeakResponderRef, type: NavigationResponder.Type)
        case strong(NavigationResponder)
        var responder: NavigationResponder? {
            switch self {
            case .weak(ref: let ref, type: _): return ref.responder
            case .strong(let responder): return responder
            }
        }
        var responderType: String {
            switch self {
            case .weak(ref: _, type: let type): return "\(type)"
            case .strong(let responder): return "\(type(of: responder))"
            }
        }
    }

    public struct ResponderRefMaker {
        fileprivate let ref: AnyResponderRef
        private init(_ ref: AnyResponderRef) {
            self.ref = ref
        }
        public static func `weak`(_ responder: (some NavigationResponder & AnyObject)) -> ResponderRefMaker {
            return .init(ResponderRef.weak(ref: WeakResponderRef(responder), type: type(of: responder)))
        }
        public static func `weak`(nullable responder: (any NavigationResponder & AnyObject)?) -> ResponderRefMaker? {
            guard let responder = responder else { return nil }
            return .init(ResponderRef.weak(ref: WeakResponderRef(responder), type: type(of: responder)))
        }
        public static func `strong`(_ responder: any NavigationResponder & AnyObject) -> ResponderRefMaker {
            return .init(ResponderRef.strong(responder))
        }
        public static func `strong`(nulable responder: (any NavigationResponder & AnyObject)?) -> ResponderRefMaker? {
            guard let responder = responder else { return nil }
            return .init(ResponderRef.strong(responder))
        }
        public static func `struct`(_ responder: some NavigationResponder) -> ResponderRefMaker {
            assert(Mirror(reflecting: responder).displayStyle == .struct, "\(type(of: responder)) is not a struct")
            return .init(ResponderRef.strong(responder))
        }
        public static func `struct`(nullable responder: (some NavigationResponder)?) -> ResponderRefMaker? {
            guard let responder = responder else { return nil }
            return .struct(responder)
        }
    }

    fileprivate final class WeakResponderRef {
        weak var responder: (NavigationResponder & AnyObject)?
        init(_ responder: (NavigationResponder & AnyObject)?) {
            self.responder = responder
        }
    }

    public var responders: [NavigationResponder] {
        return responderRefs.enumerated().reversed().compactMap { (idx, ref) in
            guard let responder = ref.responder else {
                responderRefs.remove(at: idx)
                return nil
            }
            return responder
        }.reversed()
    }

}

// MARK: - Forwarding
extension DistributedNavigationDelegate {

    /// Responders can implement custom WKWebView delegate actions
    /// this may affect the designated method not being called, be careful
    public func registerCustomDelegateMethodHandler(_ handler: ResponderRefMaker, for selector: Selector) {
        assert(customDelegateMethodHandlers[selector] == nil)
        customDelegateMethodHandlers[selector] = handler.ref
    }
    public func registerCustomDelegateMethodHandler(_ handler: ResponderRefMaker, for selectors: [Selector]) {
        for selector in selectors {
            registerCustomDelegateMethodHandler(handler, for: selector)
        }
    }

    public override func responds(to selector: Selector!) -> Bool {
        if !super.responds(to: selector) {
            return customDelegateMethodHandlers[selector] != nil
        }
        return true
    }

    public override func forwardingTarget(for selector: Selector!) -> Any? {
        return customDelegateMethodHandlers[selector]?.responder
    }

}

private protocol AnyResponderRef {
    var responder: NavigationResponder? { get }
    var responderType: String { get }
}
