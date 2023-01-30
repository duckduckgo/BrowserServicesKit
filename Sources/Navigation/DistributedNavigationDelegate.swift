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
// swiftlint:disable large_tuple
public final class DistributedNavigationDelegate: NSObject {

    private var responders = ResponderChain<NavigationResponder>()
    private var customDelegateMethodHandlers = [Selector: ResponderRef<NavigationResponder>]()
    private let logger: OSLog

    /// Developer-defined mapping to an expected main frame WKNavigation or "other" navigation type matching URL (for js-redirects).
    /// May incude custom NavigationTypes defined using UserInfo
    private var expectedNavigationAction: (condition: NavigationMatchingCondition?, navigationType: NavigationType?, redirectHistory: [NavigationAction]?)?
    /// sets developer-defined NavigationType for a next expected WKNavigationAction
    @MainActor
    public func setExpectedNavigationType(_ navigationType: NavigationType, matching condition: NavigationMatchingCondition, keepingCurrentNavigationRedirectHistory: Bool = false) {
        expectedNavigationAction = (condition, navigationType, keepingCurrentNavigationRedirectHistory ? currentNavigation?.navigationActions : nil)
    }

    /// approved navigation before `navigationDidStart` event received (useful for authentication challenge and redirect events)
    private var navigationExpectedToStart: Navigation? {
        didSet {
            updateCurrentNavigation()
        }
    }

    // currently processed NavigationAction decision Task
    private var navigationActionDecisionTask: Task<Void, Never>? {
        willSet {
            navigationActionDecisionTask?.cancel()
        }
    }
    // useful for non-mainframe navigation actions to keep an initiating action ref
    private var expectedDownloadNavigationAction: NavigationAction?
    private var expectedDownloadNavigationResponse: NavigationResponse?

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
        guard self.currentNavigation !== currentNavigation else { return }
        self.currentNavigation = currentNavigation
    }

    /// last BackForwardList item committed into WebView
    @Published public private(set) var currentHistoryItemIdentity: HistoryItemIdentity?
    private func updateCurrentHistoryItemIdentity(_ currentItem: WKBackForwardListItem?) {
        guard let identity = currentItem?.identity,
              currentHistoryItemIdentity != identity
        else { return }

        currentHistoryItemIdentity = identity
    }

    public init(logger: OSLog) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.logger = logger
    }

    /** set responder chain for Navigation Events with defined ownership and nullability:
     ```
     navigationDelegate.setResponders( .weak(responder1), .weak(nullable: responder2), .strong(responder3), .strong(nullable: responder4))
     ```
     **/
    public func setResponders(_ refs: ResponderRefMaker<NavigationResponder>?...) {
        dispatchPrecondition(condition: .onQueue(.main))

        responders.setResponders(refs.compactMap { $0 })
    }

}

public enum NavigationMatchingCondition: Equatable {
#if _MAIN_FRAME_NAVIGATION_ENABLED
    case navigation(WKNavigation)
#endif
    case other(url: URL)

    func matches(_ navigationAction: WKNavigationAction) -> Bool {
        switch self {
#if _MAIN_FRAME_NAVIGATION_ENABLED
        case .navigation(let navigation):
            return navigationAction.mainFrameNavigation === navigation
#endif
        case .other(url: let url):
            return navigationAction.navigationType == .other && navigationAction.request.url?.matches(url) == true
        }
    }
}

private extension DistributedNavigationDelegate {

    /// continues until first non-nil Navigation Responder decision and returned to the `completion` callback
    func makeAsyncDecision<T>(decide: @escaping @MainActor (NavigationResponder) async -> T?,
                              completion: @escaping @MainActor (T?) -> Void,
                              cancellation: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task.detached { @MainActor [responders] in
            var result: T?
            for responder in responders {
                guard !Task.isCancelled else {
                    cancellation()
                    return
                }

#if DEBUG
                let typeOfResponder = type(of: responder)
                let timeoutWorkItem = DispatchWorkItem {
                    assertionFailure("decision making is taking longer than expected, probably there‘s a leak in \(typeOfResponder)")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: timeoutWorkItem)
                defer { // swiftlint:disable:this inert_defer
                    timeoutWorkItem.cancel()
                }
#endif
                if let decision = await decide(responder) {
                    result = decision
                    break
                }
            }
            guard !Task.isCancelled else {
                cancellation()
                return
            }

            completion(result)
        }
    }

    func makeAsyncDecision<T>(decide: @escaping @MainActor (NavigationResponder) async -> T?,
                              completion: @escaping @MainActor (T?) -> Void) {
        _=makeAsyncDecision(decide: decide, completion: completion, cancellation: {
            completion(nil)
        })
    }

    /// Maps `WKNavigationAction` to `NavigationAction` according to an active server redirect or an expected NavigationType
    @MainActor
    func navigationAction(for navigationAction: WKNavigationAction, in webView: WKWebView) -> NavigationAction {
        guard navigationAction.targetFrame?.isMainFrame == true else {
            return NavigationAction(webView: webView, navigationAction: navigationAction, currentHistoryItemIdentity: currentHistoryItemIdentity, redirectHistory: nil)
        }

        let navigationType: NavigationType?
        let redirectHistory: [NavigationAction]?
        if let expected = expectedNavigationAction,
           expected.condition?.matches(navigationAction) ?? true {
            // client-defined or client-redirect expected navigation type matching current main frame navigation URL
            navigationType = expected.navigationType
            redirectHistory = expected.redirectHistory
            // ! don‘t nullify the expectedNavigationAction until the decision is taken

        } else if let startedNavigation,
                  case .started = startedNavigation.state,
                  // redirect Navigation Action should always have sourceFrame set:
                  // https://github.com/WebKit/WebKit/blob/c39358705b79ccf2da3b76a8be6334e7e3dfcfa6/Source/WebKit/UIProcess/WebPageProxy.cpp#L5675
                  navigationAction.safeSourceFrame != nil,
                  navigationAction.isRedirect != false {
            // received server redirect
            navigationType = .redirect(.server)
            redirectHistory = startedNavigation.navigationActions

        } else {
            navigationType = nil // resolve from WKNavigationAction navigation type
            redirectHistory = nil
        }

        return NavigationAction(webView: webView, navigationAction: navigationAction, currentHistoryItemIdentity: currentHistoryItemIdentity, redirectHistory: redirectHistory, navigationType: navigationType)
    }

}

// MARK: - WKNavigationDelegate
extension DistributedNavigationDelegate: WKNavigationDelegatePrivate {

    // MARK: Policy making

    @MainActor
    public func webView(_ webView: WKWebView, decidePolicyFor wkNavigationAction: WKNavigationAction, preferences wkPreferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        let navigationAction = navigationAction(for: wkNavigationAction, in: webView)
        os_log("decidePolicyFor: %s: %s", log: logger, type: .default, navigationAction.debugDescription, wkNavigationAction.mainFrameNavigation?.description ?? "<nil>")

        // initial `about:` scheme navigation doesn‘t wait for decision
        if (navigationAction.url.scheme.map(URL.NavigationalScheme.init) == .about
            && (webView.backForwardList.currentItem == nil || navigationAction.navigationType == .sessionRestoration))
            // same-document navigations do the same
            || navigationAction.isSameDocumentNavigation {

            decisionHandler(.allow, wkPreferences)
            self.willStart(navigationAction, withMainFrameNavigation: wkNavigationAction.mainFrameNavigation)

            return
        }

        var preferences = NavigationPreferences(userAgent: webView.customUserAgent, preferences: wkPreferences)
        let task = makeAsyncDecision { responder in
            dispatchPrecondition(condition: .onQueue(.main))

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
                if let userAgent = preferences.userAgent {
                    webView.customUserAgent = userAgent
                }
                decisionHandler(.allow, preferences.applying(to: wkPreferences))
                self.willStart(navigationAction, withMainFrameNavigation: wkNavigationAction.mainFrameNavigation)

            case .cancel(let relatedAction):
                self.willCancel(navigationAction, with: relatedAction)
                decisionHandler(.cancel, wkPreferences)
                self.didCancel(navigationAction, with: relatedAction)

            case .download:
                self.willStartDownload(with: navigationAction, in: webView)
                decisionHandler(.downloadPolicy, wkPreferences)
            }
            // don‘t release the original WKNavigationAction until the end
            withExtendedLifetime(wkNavigationAction) {}

        } cancellation: {
            dispatchPrecondition(condition: .onQueue(.main))

            os_log("Task cancelled for %s", log: self.logger, type: .default, navigationAction.debugDescription)
            decisionHandler(.cancel, wkPreferences)
        }

        if navigationAction.isForMainFrame {
            self.navigationActionDecisionTask = task
        }
    }

    @MainActor
    private func willStart(_ navigationAction: NavigationAction, withMainFrameNavigation wkNavigation: WKNavigation?) {
        guard navigationAction.isForMainFrame else { return }
        os_log("willStart %s with %s", log: logger, type: .default, navigationAction.debugDescription, wkNavigation?.description ?? "<nil>")

        let identity = wkNavigation.map(NavigationIdentity.init)
        if let redirectedNavigation = self.redirectedNavigation(for: navigationAction),
            identity == redirectedNavigation.identity
            // if navigationAction._mainFrameNavigation disabled
            || identity == nil {

            // overwrite navigationAction for redirected navigation
            redirectedNavigation.redirected(with: navigationAction)
            self.navigationExpectedToStart = nil
        } else if navigationAction.isSameDocumentNavigation || (startedNavigation != nil && identity == startedNavigation!.identity) {
            // no new navigation will start
        } else {
            let navigation = Navigation.expected(navigationAction: navigationAction, identity: identity ?? .expected)
            self.navigationExpectedToStart = navigation

            if let wkNavigation {
                // ensure Navigation object lifetime is bound to the WKNavigation in case it‘s not properly started or finished
                WKNavigationLifetimeTracker(navigation: navigation).bind(to: wkNavigation)
                wkNavigation.navigation = navigation
            }
        }

        for responder in responders {
            responder.willStart(navigationAction)
        }
    }

    @MainActor
    private func redirectedNavigation(for navigationAction: NavigationAction) -> Navigation? {
        guard let startedNavigation else { return nil }

        switch startedNavigation.state {
        case .started, .redirected:
            guard case .redirect(.server) = navigationAction.navigationType else { break }
            return startedNavigation
        case .responseReceived:
            // current navigation still didn‘t receive didFinish or didFail event yet
            // further operations (didReceiveAuthenticationChallenge, didReceiveServerRedirect, didStart)
            // should use `navigationExpectedToStart`, let the `startedNavigation` finish
            break
        case .expected:
            assertionFailure("dropping previous expectated navigation: \(startedNavigation.navigationAction.debugDescription)")
        case .finished, .failed:
            assertionFailure("finished navigation should be nil")
        }
        return nil
    }

    @MainActor
    private func willStartDownload(with navigationAction: NavigationAction, in webView: WKWebView) {
        expectedDownloadNavigationAction = navigationAction
        for responder in responders {
            responder.navigationAction(navigationAction, willBecomeDownloadIn: webView)
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
        let navigation = navigationExpectedToStart ?? startedNavigation
        navigation?.challengeRececived()

        os_log("didReceive challenge: %s: %s", log: logger, type: .default, navigation?.debugDescription ?? webView.debugDescription, challenge.protectionSpace.description)

        makeAsyncDecision { responder in
            dispatchPrecondition(condition: .onQueue(.main))

            guard let decision = await responder.didReceive(challenge, for: navigation) else { return .next }
            os_log("%s: %s decision: %s", log: self.logger, type: .default, String(describing: challenge), "\(type(of: responder))", decision.description)

            return decision

        } completion: { (decision: AuthChallengeDisposition?) in
            dispatchPrecondition(condition: .onQueue(.main))

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
        guard let navigation = wkNavigation?.navigation ?? navigationExpectedToStart ?? startedNavigation else {
            assertionFailure("No navigation is expected to receive server redirect")
            return
        }

        navigation.didReceiveServerRedirect(for: wkNavigation)
        os_log("didReceiveServerRedirect %s for: %s", log: logger, type: .default, navigation.navigationAction.debugDescription, navigation.debugDescription)

        for responder in responders {
            responder.didReceiveServerRedirect(navigation.navigationAction, for: navigation)
        }
    }

    // MARK: Navigation
    @MainActor
    public func webView(_ webView: WKWebView, navigation: WKNavigation, didSameDocumentNavigation navigationType: Int) {
        if let forwardingTarget = forwardingTarget(for: #selector(webView(_:navigation:didSameDocumentNavigation:))) {
            withUnsafePointer(to: forwardingTarget) { $0.withMemoryRebound(to: WKNavigationDelegatePrivate.self, capacity: 1) { $0 } }.pointee
                .webView?(webView, navigation: navigation, didSameDocumentNavigation: navigationType)
        }

        os_log("didSameDocumentNavigation %s: %d", log: logger, type: .default, navigation.debugDescription, navigationType)

        if navigationType == 0 {
            updateCurrentHistoryItemIdentity(webView.backForwardList.currentItem)
        }
    }

    @MainActor
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation wkNavigation: WKNavigation?) {
        let navigation: Navigation
        if let expectedNavigation = navigationExpectedToStart, wkNavigation != nil || expectedNavigation.navigationAction.navigationType == .sessionRestoration {
            // regular flow: start .expected navigation
            expectedNavigation.started(wkNavigation)
            navigation = expectedNavigation
        } else {
            assertionFailure("session restoration happening without NavigationAction")
            navigation = .started(navigationAction: .sessionRestoreNavigation(webView: webView), navigation: wkNavigation)
        }
        self.startedNavigation = navigation
        self.navigationExpectedToStart = nil

        os_log("didStart: %s", log: logger, type: .default, navigation.debugDescription)
        assert(navigation.navigationAction.navigationType.redirect?.isServer != true, "server redirects shouldn‘t call didStartProvisionalNavigation")

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
            dispatchPrecondition(condition: .onQueue(.main))

            guard let decision = await responder.decidePolicy(for: navigationResponse, currentNavigation: startedNavigation) else { return .next }
            os_log("%s: %s decision: %s", log: self.logger, type: .default, navigationResponse.debugDescription, "\(type(of: responder))", "\(decision)")

            return decision

        } completion: { [weak self] (decision: NavigationResponsePolicy?) in
            dispatchPrecondition(condition: .onQueue(.main))

            switch decision {
            case .allow, .none:
                decisionHandler(.allow)
            case .cancel:
                decisionHandler(.cancel)
            case .download:
                self?.willStartDownload(with: navigationResponse, in: webView)
                decisionHandler(.downloadPolicy)
            }
        }
    }

    @MainActor
    private func willStartDownload(with navigationResponse: NavigationResponse, in webView: WKWebView) {
        expectedDownloadNavigationResponse = navigationResponse
        for responder in responders {
            responder.navigationResponse(navigationResponse, willBecomeDownloadIn: webView)
        }
    }

    @MainActor
    public func webView(_ webView: WKWebView, didCommit wkNavigation: WKNavigation?) {
        guard let navigation = wkNavigation?.navigation ?? startedNavigation else {
            assertionFailure("Unexpected didCommitNavigation")
            return
        }
        updateCurrentHistoryItemIdentity(webView.backForwardList.currentItem)
        navigation.committed(wkNavigation)
        os_log("didCommit: %s", log: logger, type: .default, navigation.debugDescription)

        for responder in responders {
            responder.didCommit(navigation)
        }
    }

#if WILLPERFORMCLIENTREDIRECT_ENABLED

    @MainActor
    public func webView(_ webView: WKWebView, willPerformClientRedirectTo url: URL, delay: TimeInterval) {
        // if method implemented in Responder using registerCustomDelegateMethodHandler(for:selector)
        if let forwardingTarget = forwardingTarget(for: #selector(webView(_:willPerformClientRedirectTo:delay:))) {
            withUnsafePointer(to: forwardingTarget) { $0.withMemoryRebound(to: WKNavigationDelegatePrivate.self, capacity: 1) { $0 } }.pointee
                .webView?(webView, willPerformClientRedirectTo: url, delay: delay)
        }

        guard let startedNavigation,
              // same-document navigation
              !(url.absoluteString.hashedSuffix != nil && startedNavigation.url.absoluteString.droppingHashedSuffix() == url.absoluteString.droppingHashedSuffix())
        else { return }

        os_log("willPerformClientRedirect to: %s, current: %s", log: logger, type: .default, url.absoluteString, startedNavigation.debugDescription)
        if expectedNavigationAction?.condition != .other(url: url) {
            // next decidePolicyForNavigationAction event should have Client Redirect navigation type
            setExpectedNavigationType(.redirect(.client(delay: delay)), matching: .other(url: url), keepingCurrentNavigationRedirectHistory: true)
        }
    }

    @MainActor
    public func webViewDidCancelClientRedirect(_ webView: WKWebView) {
        // if method implemented in Responder using registerCustomDelegateMethodHandler(for:selector)
        if let forwardingTarget = forwardingTarget(for: #selector(webViewDidCancelClientRedirect(_:))) {
            withUnsafePointer(to: forwardingTarget) { $0.withMemoryRebound(to: WKNavigationDelegatePrivate.self, capacity: 1) { $0 } }.pointee
                .webViewDidCancelClientRedirect?(webView)
        }

        if case .client = expectedNavigationAction?.navigationType?.redirect {
            expectedNavigationAction = nil
        }
    }
#endif

    // MARK: Completion

    @MainActor
    public func webView(_ webView: WKWebView, didFinish wkNavigation: WKNavigation?) {
        let navigation = wkNavigation?.navigation ?? startedNavigation
        guard let navigation, navigation.identity == wkNavigation.map(NavigationIdentity.init) || wkNavigation == nil else {
            os_log("dropping didFinishNavigation: %s, as another navigation is active: %s", log: logger, type: .default, wkNavigation?.description ?? "<nil>", navigation?.debugDescription ?? "<nil>")
            return
        }

        updateCurrentHistoryItemIdentity(webView.backForwardList.currentItem)
        navigation.didFinish(wkNavigation)
        os_log("didFinish: %s", log: logger, type: .default, navigation.debugDescription)

        for responder in responders {
            responder.navigationDidFinish(navigation)
        }

        if self.startedNavigation === navigation {
            self.startedNavigation = nil
        }
    }

    @MainActor
    public func webView(_ webView: WKWebView, didFail wkNavigation: WKNavigation?, withError error: Error) {
        let error = error as? WKError ?? WKError(_nsError: error as NSError)
        let navigation = wkNavigation?.navigation ?? startedNavigation
        guard let navigation, navigation.identity == wkNavigation.map(NavigationIdentity.init) || wkNavigation == nil else {
            os_log("dropping didFailNavigation: %s with: %s, as another navigation is active: %s", log: logger, type: .default, wkNavigation?.description ?? "<nil>", error.errorDescription ?? error.localizedDescription, navigation?.debugDescription ?? "<nil>")
            return
        }

        updateCurrentHistoryItemIdentity(webView.backForwardList.currentItem)
        navigation.didFail(wkNavigation, with: error)
        os_log("didFail %s: %s", log: logger, type: .default, navigation.debugDescription, error.errorDescription ?? error.localizedDescription)

        for responder in responders {
            responder.navigation(navigation, didFailWith: error, isProvisioned: false)
        }

        if self.startedNavigation === navigation {
            self.startedNavigation = nil
        }
    }

    @MainActor
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation wkNavigation: WKNavigation?, withError error: Error) {
        let error = error as? WKError ?? WKError(_nsError: error as NSError)
        let navigation = wkNavigation?.navigation ?? startedNavigation
        guard let navigation, navigation.identity == wkNavigation.map(NavigationIdentity.init) || wkNavigation == nil else {
            os_log("dropping didFailProvisionalNavigation: %s with: %s, as another navigation is active: %s", log: logger, type: .default, wkNavigation?.description ?? "<nil>", error.errorDescription ?? error.localizedDescription, navigation?.debugDescription ?? "<nil>")
            return
        }

        updateCurrentHistoryItemIdentity(webView.backForwardList.currentItem)
        navigation.didFail(wkNavigation, with: error)
        os_log("didFail provisional %s: %s", log: logger, type: .default, navigation.debugDescription, error.errorDescription ?? error.localizedDescription)

        for responder in responders {
            responder.navigation(navigation, didFailWith: error, isProvisioned: true)
        }

        if self.startedNavigation === navigation {
            self.startedNavigation = nil
        }
    }

    @MainActor
    public func webView(_ webView: WKWebView, didFinishLoadWith request: URLRequest, in frame: WKFrameInfo) {
        // if method implemented in Responder using registerCustomDelegateMethodHandler(for:selector)
        if let forwardingTarget = forwardingTarget(for: #selector(webView(_:didFinishLoadWith:in:))) {
            withUnsafePointer(to: forwardingTarget) { $0.withMemoryRebound(to: WKNavigationDelegatePrivate.self, capacity: 1) { $0 } }.pointee
                .webView?(webView, didFinishLoadWith: request, in: frame)
        }

        updateCurrentHistoryItemIdentity(webView.backForwardList.currentItem)
    }

    @MainActor
    public func webView(_ webView: WKWebView, didFailProvisionalLoadWith request: URLRequest, in frame: WKFrameInfo, with error: Error) {
        // if method implemented in Responder using registerCustomDelegateMethodHandler(for:selector)
        if let forwardingTarget = forwardingTarget(for: #selector(webView(_:didFailProvisionalLoadWith:in:with:))) {
            withUnsafePointer(to: forwardingTarget) { $0.withMemoryRebound(to: WKNavigationDelegatePrivate.self, capacity: 1) { $0 } }.pointee
                .webView?(webView, didFailProvisionalLoadWith: request, in: frame, with: error)
        }

        updateCurrentHistoryItemIdentity(webView.backForwardList.currentItem)
    }

    @MainActor
    @available(macOS 11.3, iOS 14.5, *) // objc does‘t care about availability
    @objc(webView:navigationAction:didBecomeDownload:)
    public func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        let navigationAction = expectedDownloadNavigationAction
            ?? NavigationAction(webView: webView, navigationAction: navigationAction, currentHistoryItemIdentity: currentHistoryItemIdentity, redirectHistory: nil)
        self.expectedDownloadNavigationAction = nil

        for responder in responders {
            responder.navigationAction(navigationAction, didBecome: download)
        }
    }

    @MainActor
    @available(macOS 11.3, iOS 14.5, *) // objc does‘t care about availability
    @objc(webView:navigationResponse:didBecomeDownload:)
    public func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        let navigationResponse = expectedDownloadNavigationResponse
            ?? NavigationResponse(navigationResponse: navigationResponse)

        for responder in responders {
            responder.navigationResponse(navigationResponse, didBecome: download, currentNavigation: startedNavigation)
        }

        if let startedNavigation, let expectedDownloadNavigationResponse,
           case .responseReceived(expectedDownloadNavigationResponse) = startedNavigation.state {
            self.startedNavigation = nil
        }
        self.expectedDownloadNavigationResponse = nil
    }

    @MainActor
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        startedNavigation?.didFail(with: WKError(WKError.Code.webContentProcessTerminated))
        os_log("%s process did terminate; current navigation: %s", log: logger, type: .default, webView.debugDescription, startedNavigation?.debugDescription ?? "<nil>")

        for responder in responders {
            responder.webContentProcessDidTerminate(currentNavigation: startedNavigation)
        }
        self.startedNavigation = nil
        self.navigationExpectedToStart = nil
        self.expectedNavigationAction = nil
    }

}

// MARK: - Forwarding
extension DistributedNavigationDelegate {

    /// Here Responders can be registered as handlers for custom WKNavigationDelegate methods not implemented in DistributedNavigationDelegate
    /// !!! BE CAREFUL:
    /// If this method is used to register one of the exclusive delegate methods of higher priority than already present in DistributedNavigationDelegate
    /// (such as one of the decidePolicyForNavigationAction (sync/async/with preferences) methods or a higher priority private API method)
    /// this will lead to the designated DistributedNavigationDelegate method not called at all.
    /// !!! Only one responder can be registered per custom method handler
    public func registerCustomDelegateMethodHandler(_ handler: ResponderRefMaker<NavigationResponder>, for selector: Selector) {
        dispatchPrecondition(condition: .onQueue(.main))
        assert(customDelegateMethodHandlers[selector] == nil)
        customDelegateMethodHandlers[selector] = handler.ref
    }
    public func registerCustomDelegateMethodHandler(_ handler: ResponderRefMaker<NavigationResponder>, for selectors: [Selector]) {
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
