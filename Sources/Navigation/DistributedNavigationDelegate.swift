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

    internal var responders = ResponderChain()
    private var customDelegateMethodHandlers = [Selector: any AnyResponderRef]()
    private let logger: OSLog

    /// approved navigation before `navigationDidStart` event received (useful for authentication challenge and redirect events)
    @MainActor
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

    /// ongoing Main Frame navigation (after `navigationDidStart` event received)
    @MainActor
    private var startedNavigation: Navigation? {
        willSet {
            startedNavigation?.didResignCurrent()
        }
        didSet {
            updateCurrentNavigation()
        }
    }

    /// published "current" navigation - represents either started or approved (expected to start) navigation
    @Published public private(set) var currentNavigation: Navigation?
    @MainActor
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
    public func setResponders(_ refs: ResponderRefMaker?...) {
        dispatchPrecondition(condition: .onQueue(.main))

        responders.setResponders(refs.compactMap { $0 })
    }

}

private extension DistributedNavigationDelegate {

    /// continues until first non-nil Navigation Responder decision and returned to the `completion` callback
    func makeAsyncDecision<T>(with responders: ResponderChain,
                              decide: @escaping @MainActor (NavigationResponder) async -> T?,
                              completion: @escaping @MainActor (T?) -> Void,
                              cancellation: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        dispatchPrecondition(condition: .onQueue(.main))
        // TO DO: ideally the Task should be executed synchronously until the first await, check it later when custom Executors arrive to Swift
        return Task.detached { @MainActor [responders] in
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

    func makeAsyncDecision<T>(with responders: ResponderChain,
                              decide: @escaping @MainActor (NavigationResponder) async -> T?,
                              completion: @escaping @MainActor (T?) -> Void) {
        _=makeAsyncDecision(with: responders, decide: decide, completion: completion, cancellation: {
            completion(nil)
        })
    }

    /// Maps `WKNavigationAction` to `NavigationAction` according to an active server redirect or an expected NavigationType
    @MainActor
    func navigation(for wkNavigationAction: WKNavigationAction, in webView: WKWebView) -> Navigation? {
        guard wkNavigationAction.targetFrame?.isMainFrame == true else {
            return nil
        }
        // only handled for main-frame navigations:
        // get WKNavigation associated with the WKNavigationAction
        // it is not `current` yet, unless it‘s a server-redirect
        let wkNavigation = wkNavigationAction.mainFrameNavigation
        let navigation: Navigation = {
            if let navigation = wkNavigation?.navigation,
               // same-document NavigationActions have a previous WKNavigation mainFrameNavigation
               !wkNavigationAction.isSameDocumentNavigation {
                // it‘s a server-redirect or a developer-initiated navigation, so the WKNavigation already has an associated Navigation object
                return navigation
            }
            return Navigation(identity: NavigationIdentity(wkNavigation), responders: responders, state: .expected(nil), isCurrent: false)
        }()
        // wkNavigation.navigation = navigation
        if wkNavigation?.navigation == nil {
            navigation.associate(with: wkNavigation)
        }

        // custom NavigationType for navigations with developer-set NavigationType
        var navigationType: NavigationType? = navigation.state.expectedNavigationType
        var redirectHistory: [NavigationAction]?
        if let startedNavigation,
           // server-redirected navigation continues with the same WKNavigation identity
           startedNavigation === navigation || navigation.identity == .expected,
           case .started = startedNavigation.state,
           // redirect Navigation Action should always have sourceFrame set:
           // https://github.com/WebKit/WebKit/blob/c39358705b79ccf2da3b76a8be6334e7e3dfcfa6/Source/WebKit/UIProcess/WebPageProxy.cpp#L5675
           wkNavigationAction.safeSourceFrame != nil,
           wkNavigationAction.isRedirect != false {

            assert(navigationType == nil)
            // server redirect received
            navigationType = .redirect(.server)
            redirectHistory = startedNavigation.navigationActions

        // client redirect
        } else if let startedNavigation,
                  // previous navigation completion is delayed until the WKNavigationAction is handled
                  case .willPerformClientRedirect(delay: let delay) = startedNavigation.state,
                  // new navigations are started for client redirects
                  startedNavigation.identity != navigation.identity {
            // user-initiated actions aren‘t client redirects
            if wkNavigationAction.isUserInitiated != true {
                navigationType = .redirect(.client(delay: delay))
                redirectHistory = startedNavigation.navigationActions
            } else {
                startedNavigation.didCancelClientRedirect()
            }
        }

        let navigationAction = NavigationAction(webView: webView, navigationAction: wkNavigationAction, currentHistoryItemIdentity: currentHistoryItemIdentity, redirectHistory: redirectHistory, navigationType: navigationType, mainFrameNavigation: navigation)
        navigation.navigationActionReceived(navigationAction)

        return navigation
    }

}

// MARK: - WKNavigationDelegate
extension DistributedNavigationDelegate: WKNavigationDelegate {

    // MARK: Policy making

    @MainActor
    public func webView(_ webView: WKWebView, decidePolicyFor wkNavigationAction: WKNavigationAction, preferences wkPreferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) { // swiftlint:disable:this function_body_length

        let navigation = navigation(for: wkNavigationAction, in: webView)
        let navigationAction = navigation?.navigationAction
            ?? NavigationAction(webView: webView, navigationAction: wkNavigationAction, currentHistoryItemIdentity: currentHistoryItemIdentity, redirectHistory: nil, mainFrameNavigation: startedNavigation)
        wkNavigationAction.navigationAction = navigationAction

        let mainFrameNavigation = withExtendedLifetime(navigation) {
            navigationAction.isForMainFrame ? navigationAction.mainFrameNavigation : nil
        }
        assert(navigationAction.mainFrameNavigation != nil || !navigationAction.isForMainFrame)
        os_log("decidePolicyFor: %s", log: logger, type: .default, navigationAction.debugDescription)

        // initial `about:` scheme navigation doesn‘t wait for decision
        if (navigationAction.url.scheme.map(URL.NavigationalScheme.init) == .about
            && (webView.backForwardList.currentItem == nil || navigationAction.navigationType == .sessionRestoration))
            // same-document navigations do the same
            || wkNavigationAction.isSameDocumentNavigation {

            // allow them right away
            decisionHandler(.allow, wkPreferences)
            if let mainFrameNavigation {
                self.willStart(mainFrameNavigation)
            }
            return
        }

        var preferences = NavigationPreferences(userAgent: webView.customUserAgent, preferences: wkPreferences)
        let task = makeAsyncDecision(with: mainFrameNavigation?.navigationResponders ?? responders) { responder in
            dispatchPrecondition(condition: .onQueue(.main))

            guard let decision = await responder.decidePolicy(for: navigationAction, preferences: &preferences) else { return .next }
            os_log("%s: %s decision: %s", log: self.logger, type: .default, navigationAction.debugDescription, "\(type(of: responder))", decision.debugDescription)

            return decision

        } completion: { (decision: NavigationActionPolicy?) in
            dispatchPrecondition(condition: .onQueue(.main))

            switch decision {
            case .allow, .none:
                if let userAgent = preferences.userAgent {
                    webView.customUserAgent = userAgent
                }
                decisionHandler(.allow, preferences.applying(to: wkPreferences))

                if let mainFrameNavigation, !mainFrameNavigation.isCurrent {
                    // another navigation is starting
                    self.startedNavigation?.didResignCurrent()
                    self.willStart(mainFrameNavigation)
                }

            case .cancel:
                decisionHandler(.cancel, wkPreferences)

            case .redirect(_, let redirect):
                assert(navigationAction.isForMainFrame)

                decisionHandler(.cancel, wkPreferences)
                redirect(webView.navigator(distributedNavigationDelegate: self, redirectedNavigation: mainFrameNavigation))

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
            // cancel previous `decidePolicyForNavigationAction` async operations when new Navigation begins
            self.navigationActionDecisionTask = task
        }
    }

    @MainActor
    private func willStart(_ navigation: Navigation) {
        os_log("willStart %s", log: logger, type: .default, navigation.debugDescription)

        if case .redirect(.client) = navigation.navigationAction.navigationType {
            // notify the original (redirected) Navigation about the redirect NavigationAction received
            // this should call the overriden ResponderChain inside `willPerformClientRedirect`
            // that in turn notifies the original responders and finishes the Navigation
            startedNavigation?.didPerformClientRedirect(with: navigation.navigationAction)
        }

        navigation.willStart()
        for responder in navigation.navigationResponders {
            responder.willStart(navigation)
        }
        navigationExpectedToStart = navigation
    }

    @MainActor
    private func willStartDownload(with navigationAction: NavigationAction, in webView: WKWebView) {
        let responders = (navigationAction.isForMainFrame ? navigationAction.mainFrameNavigation?.navigationResponders : nil) ?? responders
        for responder in responders {
            responder.navigationAction(navigationAction, willBecomeDownloadIn: webView)
        }
    }

    // MARK: Pre-Navigation: Auth, Server Redirects

    @MainActor
    public func webView(_ webView: WKWebView,
                        didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // previous navigation may stil be expecting completion at this point
        let navigation = navigationExpectedToStart ?? startedNavigation
        navigation?.challengeRececived()

        os_log("didReceive challenge: %s: %s", log: logger, type: .default, navigation?.debugDescription ?? webView.debugDescription, challenge.protectionSpace.description)

        makeAsyncDecision(with: navigation?.navigationResponders ?? responders) { responder in
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

        for responder in navigation.navigationResponders {
            responder.didReceiveRedirect(navigation.navigationAction, for: navigation)
        }
    }

    // MARK: Navigation

    @MainActor
    @objc(_webView:navigation:didSameDocumentNavigation:)
    public func webView(_ webView: WKWebView, wkNavigation: WKNavigation?, didSameDocumentNavigation navigationType: Int) {
        os_log("didSameDocumentNavigation %s: %d", log: logger, type: .default, wkNavigation.debugDescription, navigationType)

        // currentHistoryItemIdentity should only change for completed navigation, not while in progress
        let navigationType = WKSameDocumentNavigationType(rawValue: navigationType)
        if case .anchorNavigation = navigationType {
            updateCurrentHistoryItemIdentity(webView.backForwardList.currentItem)
        }

        for responder in responders {
            responder.navigation(wkNavigation?.navigation, didSameDocumentNavigationOf: navigationType)
        }
    }

    @MainActor
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation wkNavigation: WKNavigation?) {
        let navigation: Navigation
        if let expectedNavigation = navigationExpectedToStart, wkNavigation != nil || expectedNavigation.navigationAction.navigationType == .sessionRestoration {
            // regular flow: start .expected navigation
            navigation = expectedNavigation
        } else {
            assertionFailure("session restoration happening without NavigationAction")
            navigation = Navigation(identity: NavigationIdentity(wkNavigation), responders: responders, state: .expected(nil), isCurrent: true)
            navigation.navigationActionReceived(.sessionRestoreNavigation(webView: webView, mainFrameNavigation: navigation))
        }

        navigation.started(wkNavigation)
        self.startedNavigation = navigation
        self.navigationExpectedToStart = nil

        os_log("didStart: %s", log: logger, type: .default, navigation.debugDescription)
        assert(navigation.navigationAction.navigationType.redirect?.isServer != true, "server redirects shouldn‘t call didStartProvisionalNavigation")

        for responder in navigation.navigationResponders {
            responder.didStart(navigation)
        }
    }

    @MainActor
    public func webView(_ webView: WKWebView, decidePolicyFor wkNavigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let navigationResponse = NavigationResponse(navigationResponse: wkNavigationResponse, mainFrameNavigation: startedNavigation)
        wkNavigationResponse.navigationResponse = navigationResponse
        if wkNavigationResponse.isForMainFrame {
            assert(startedNavigation != nil)
            startedNavigation?.receivedResponse(navigationResponse)
        }

        os_log("decidePolicyFor: %s", log: logger, type: .default, navigationResponse.debugDescription)

        let responders = (navigationResponse.isForMainFrame ? startedNavigation?.navigationResponders : nil) ?? responders
        makeAsyncDecision(with: responders) { responder in
            dispatchPrecondition(condition: .onQueue(.main))

            guard let decision = await responder.decidePolicy(for: navigationResponse) else { return .next }
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

    // MARK: Client Redirect

#if WILLPERFORMCLIENTREDIRECT_ENABLED

    // swiftlint:disable function_body_length
    // swiftlint:disable cyclomatic_complexity
    @MainActor
    @objc(_webView:willPerformClientRedirectToURL:delay:)
    public func webView(_ webView: WKWebView, willPerformClientRedirectTo url: URL, delay: TimeInterval) {
        for responder in responders {
            responder.webViewWillPerformClientRedirect(to: url, withDelay: delay)
        }

        // willPerformClientRedirect happens whenever WebView is navigated via JS or Refresh header
        // we only consider this a "client redirect" when there‘s an ongoing Navigation
        guard let redirectedNavigation = startedNavigation,
              redirectedNavigation.state.isResponseReceived,
              // don‘t handle same-document navigations
              !(url.absoluteString.hashedSuffix != nil && redirectedNavigation.url.absoluteString.droppingHashedSuffix() == url.absoluteString.droppingHashedSuffix())
        else { return }

        os_log("willPerformClientRedirect to: %s, current: %s", log: logger, type: .default, url.absoluteString, redirectedNavigation.debugDescription)

        // keep the original Navigation non-finished until the redirect NavigationAction is received
        let originalResponders = redirectedNavigation.navigationResponders

        // notify original Navigation responders after the redirect NavigationAction is received
        var sendDidFinishToResponders: ((Navigation) -> Void)?
        // override the original Navigation ResponderChain to postpone didFinish event
        // otherwise the `startedNavigation` would be set to nil and won‘t be related to new Navigation
        var delayedFinishItem: DispatchWorkItem?
        var navigationError: WKError?
        redirectedNavigation.overrideResponders(redirected: { navigationAction, navigation in
            // called from `decidePolicyForNavigationAction`: `startedNavigation.didPerformClientRedirect(with: navigationAction)`
            guard !navigation.isCompleted else { return }

            delayedFinishItem?.cancel()

            // send `didReceiveRedirect` to the original Navigation ResponderChain
            for responder in originalResponders {
                responder.didReceiveRedirect(navigationAction, for: navigation)
            }

            guard let sendDidFinish = sendDidFinishToResponders else { return }
            // set Navigation state to `finished`
            navigation.didSendDidPerformClientRedirectToResponders(with: navigationError)
            // send `navigationDidFinish` to the original Navigation ResponderChain (if `navigationDidFinish` already received)
            sendDidFinish(navigation)
            sendDidFinishToResponders = nil

        }, navigationDidFinish: { navigation in
            let sendDidFinish = { (navigation: Navigation) in
                if !navigation.isCompleted {
                    navigation.didFinish()
                }
                for responder in originalResponders {
                    responder.navigationDidFinish(navigation)
                }
            }
            guard !navigation.isCompleted else {
                // in case the navigationDidFinish is received after the `redirected` override already handled, send it now
                sendDidFinish(navigation)
                return
            }

            sendDidFinishToResponders = sendDidFinish
            // navigationDidFinish is expected to happen before receiving the redirect NavigationAction
            // here we delay it to connect current navigation with the new one
            delayedFinishItem = DispatchWorkItem {
                sendDidFinishToResponders?(navigation)
                sendDidFinishToResponders = nil
            }
            // normally the DispatchWorkItem would never be executed
            // just in case anything goes wrong we would still send the didFinish after some delay
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.5, execute: delayedFinishItem!)

        }, navigationDidFail: { navigation, error in
            // normally we should receive "navigationDidFinish", but handling didFail the same way
            let sendDidFinish = { (navigation: Navigation) in
                if !navigation.isCompleted {
                    navigation.didFail(with: error)
                }
                for responder in originalResponders {
                    responder.navigation(navigation, didFailWith: error)
                }
            }
            guard !navigation.isCompleted else {
                sendDidFinish(navigation)
                return
            }

            sendDidFinishToResponders = sendDidFinish
            navigationError = error

            delayedFinishItem = DispatchWorkItem {
                sendDidFinishToResponders?(navigation)
                sendDidFinishToResponders = nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.5, execute: delayedFinishItem!)
        })
        // set Navigation state to .redirected and expect the redirect NavigationAction
        redirectedNavigation.willPerformClientRedirect(to: url, delay: delay)
    }
    // swiftlint:enable function_body_length
    // swiftlint:enable cyclomatic_complexity

    @MainActor
    @objc(_webViewDidCancelClientRedirect:)
    public func webViewDidCancelClientRedirect(_ webView: WKWebView) {
        os_log("webViewDidCancelClientRedirect", log: logger, type: .default)

        for responder in responders {
            responder.webViewDidCancelClientRedirect(currentNavigation: startedNavigation)
        }

        if case .willPerformClientRedirect = startedNavigation?.state {
            startedNavigation?.didCancelClientRedirect()
        }
    }

#else
    @nonobjc public func webView(_: WKWebView, willPerformClientRedirectTo _: URL, delay: TimeInterval) {}
#endif

    // MARK: Completion

    @MainActor
    public func webView(_ webView: WKWebView, didFinish wkNavigation: WKNavigation?) {
        let navigation = wkNavigation?.navigation ?? startedNavigation
        guard let navigation,
              navigation.identity == wkNavigation.map(NavigationIdentity.init) || wkNavigation == nil
        else {
            os_log("dropping didFinishNavigation: %s, as another navigation is active: %s", log: logger, type: .default, wkNavigation?.description ?? "<nil>", navigation?.debugDescription ?? "<nil>")
            return
        }

        updateCurrentHistoryItemIdentity(webView.backForwardList.currentItem)
        navigation.didFinish(wkNavigation)
        os_log("didFinish: %s", log: logger, type: .default, navigation.debugDescription)

        for responder in navigation.navigationResponders {
            responder.navigationDidFinish(navigation)
        }

        if self.startedNavigation === navigation {
            if case .willPerformClientRedirect = navigation.state {
                // expecting didPerformClientRedirect
                return
            }
            self.startedNavigation = nil
        }
    }

    @MainActor
    public func webView(_ webView: WKWebView, didFail wkNavigation: WKNavigation?, withError error: Error) {
        self.webView(webView, didFail: wkNavigation, isProvisional: false, with: error)
    }

    @MainActor
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation wkNavigation: WKNavigation?, withError error: Error) {
        self.webView(webView, didFail: wkNavigation, isProvisional: true, with: error)
    }

    @MainActor
    private func webView(_ webView: WKWebView, didFail wkNavigation: WKNavigation?, isProvisional: Bool, with error: Error) {
        let error = error as? WKError ?? WKError(_nsError: error as NSError)
        let navigation = wkNavigation?.navigation ?? startedNavigation

        guard let navigation, navigation.identity == wkNavigation.map(NavigationIdentity.init) || wkNavigation == nil else {
            os_log("dropping didFail%sNavigation: %s with: %s, as another navigation is active: %s", log: logger, type: .default, isProvisional ? "Provisional" : "", wkNavigation?.description ?? "<nil>", error.errorDescription ?? error.localizedDescription, navigation?.debugDescription ?? "<nil>")
            return
        }

        updateCurrentHistoryItemIdentity(webView.backForwardList.currentItem)
        navigation.didFail(wkNavigation, with: error)
        os_log("didFail %s: %s", log: logger, type: .default, navigation.debugDescription, error.errorDescription ?? error.localizedDescription)

        for responder in navigation.navigationResponders {
            responder.navigation(navigation, didFailWith: error)
        }

        if self.startedNavigation === navigation {
            if case .willPerformClientRedirect = navigation.state {
                // expecting didPerformClientRedirect
                return
            }
            self.startedNavigation = nil
        }
    }

    @MainActor
    @objc(_webView:didFinishLoadWithRequest:inFrame:)
    public func webView(_ webView: WKWebView, didFinishLoadWith request: URLRequest, in frame: WKFrameInfo) {
        updateCurrentHistoryItemIdentity(webView.backForwardList.currentItem)

        for responder in responders {
            responder.didFinishLoad(with: request, in: frame)
        }
    }

    @MainActor
    @objc(_webView:didFailProvisionalLoadWithRequest:inFrame:withError:)
    public func webView(_ webView: WKWebView, didFailProvisionalLoadWith request: URLRequest, in frame: WKFrameInfo, with error: Error) {
        updateCurrentHistoryItemIdentity(webView.backForwardList.currentItem)

        for responder in responders {
            responder.didFailProvisionalLoad(with: request, in: frame, with: error)
        }
    }

    // MARK: Downloads

    @MainActor
    private func willStartDownload(with navigationResponse: NavigationResponse, in webView: WKWebView) {
        let responders = (navigationResponse.isForMainFrame ? navigationResponse.mainFrameNavigation?.navigationResponders : nil) ?? responders
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

        for responder in navigation.navigationResponders {
            responder.didCommit(navigation)
        }
    }

    @MainActor
    @available(macOS 11.3, iOS 14.5, *) // objc does‘t care about availability
    @objc(webView:navigationAction:didBecomeDownload:)
    public func webView(_ webView: WKWebView, navigationAction wkNavigationAction: WKNavigationAction, didBecome download: WKDownload) {
        let navigationAction = wkNavigationAction.navigationAction ?? {
            assertionFailure("WKNavigationAction has no associated NavigationAction")
            return NavigationAction(webView: webView, navigationAction: wkNavigationAction, currentHistoryItemIdentity: currentHistoryItemIdentity, redirectHistory: nil, mainFrameNavigation: startedNavigation)
        }()
        os_log("navigationActionDidBecomeDownload: %s", log: logger, type: .default, navigationAction.debugDescription)

        let responders = (navigationAction.isForMainFrame ? navigationAction.mainFrameNavigation?.navigationResponders : nil) ?? responders
        for responder in responders {
            responder.navigationAction(navigationAction, didBecome: download)
        }

        if navigationAction.isForMainFrame {
            navigationAction.mainFrameNavigation?.didFail(with: WKError(.frameLoadInterruptedByPolicyChange))
        }
        if navigationAction.isForMainFrame,
           let navigation = navigationAction.mainFrameNavigation {

            navigation.didFail(with: WKError(.frameLoadInterruptedByPolicyChange))
            if startedNavigation === navigation {
                self.startedNavigation = nil
            }
        }
    }

    @MainActor
    @available(macOS 11.3, iOS 14.5, *) // objc does‘t care about availability
    @objc(webView:navigationResponse:didBecomeDownload:)
    public func webView(_ webView: WKWebView, navigationResponse wkNavigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        let navigationResponse = wkNavigationResponse.navigationResponse ?? {
            assertionFailure("WKNavigationResponse has no associated NavigationResponse")
            return NavigationResponse(navigationResponse: wkNavigationResponse, mainFrameNavigation: startedNavigation)
        }()
        os_log("navigationResponseDidBecomeDownload: %s", log: logger, type: .default, navigationResponse.debugDescription)

        let responders = (navigationResponse.isForMainFrame ? navigationResponse.mainFrameNavigation?.navigationResponders : nil) ?? responders
        for responder in responders {
            responder.navigationResponse(navigationResponse, didBecome: download)
        }

        if navigationResponse.isForMainFrame,
           let navigation = navigationResponse.mainFrameNavigation {

            navigation.didFail(with: WKError(.frameLoadInterruptedByPolicyChange))
            if startedNavigation === navigation {
                self.startedNavigation = nil
            }
        }
    }

    // MARK: Termination

    @MainActor
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        self.webView(webView, processDidTerminateWith: nil)
    }

#if TERMINATE_WITH_REASON_ENABLED
    @MainActor
    @objc(_webView:webContentProcessDidTerminateWithReason:)
    public func webView(_ webView: WKWebView, webContentProcessDidTerminateWith reason: Int) {
        self.webView(webView, processDidTerminateWith: WKProcessTerminationReason(rawValue: reason))
    }
#endif

    @MainActor
    private func webView(_ webView: WKWebView, processDidTerminateWith reason: WKProcessTerminationReason?) {
        os_log("%s webContentProcessDidTerminateWithReason: %d", log: logger, type: .default, webView.debugDescription, reason?.rawValue ?? -1)

        for responder in responders {
            responder.webContentProcessDidTerminate(with: reason ?? .init(rawValue: Int.max))
        }
        if startedNavigation != nil {
            var userInfo = [String: Any]()
            if let reason {
                userInfo[WKProcessTerminationReason.userInfoKey] = reason
            }
            let error = WKError(WKError.Code.webContentProcessTerminated, userInfo: userInfo)
            self.webView(webView, didFail: nil, isProvisional: true, with: error)
            self.startedNavigation = nil
        }
        self.navigationExpectedToStart = nil
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
    public func registerCustomDelegateMethodHandler(_ handler: ResponderRefMaker, forSelectorNamed selectorStr: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        let selector = NSSelectorFromString(selectorStr)
        assert(customDelegateMethodHandlers[selector] == nil)
        assert((handler.ref.responder as? NSObject)!.responds(to: selector))
        customDelegateMethodHandlers[selector] = handler.ref
    }
    
    public func registerCustomDelegateMethodHandler(_ handler: ResponderRefMaker, forSelectorsNamed selectors: [String]) {
        for selector in selectors {
            registerCustomDelegateMethodHandler(handler, forSelectorNamed: selector)
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
