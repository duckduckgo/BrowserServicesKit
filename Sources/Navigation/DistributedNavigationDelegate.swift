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
import WebKit

public final class DistributedNavigationDelegate: NSObject {

    internal var responders = ResponderChain()
    private var customDelegateMethodHandlers = [Selector: any AnyResponderRef]()

    private let getLog: () -> OSLog
    private var log: OSLog {
        getLog()
    }

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

#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
    /// last BackForwardList item committed into WebView
    @Published public private(set) var currentHistoryItemIdentity: HistoryItemIdentity?
    private func updateCurrentHistoryItemIdentity(_ currentItem: WKBackForwardListItem?) {
        guard let identity = currentItem?.identity,
              currentHistoryItemIdentity != identity
        else { return }

        currentHistoryItemIdentity = identity
    }
#else
    private var currentHistoryItemIdentity: HistoryItemIdentity? { nil }
#endif

    public init(log: @escaping @autoclosure () -> OSLog) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.getLog = log

#if !_MAIN_FRAME_NAVIGATION_ENABLED
        _=WKWebView.swizzleLoadMethodOnce
#endif
        _=WKNavigationAction.swizzleRequestOnce
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

#if DEBUG
    static var sigIntRaisedForResponders = Set<String>()
#endif

    // swiftlint:disable function_parameter_count
    /// continues until first non-nil Navigation Responder decision and returned to the `completion` callback
    func makeAsyncDecision<T>(for actionDebugInfo: some CustomDebugStringConvertible,
                              boundToLifetimeOf webView: WKWebView,
                              with responders: ResponderChain,
                              decide: @escaping @MainActor (NavigationResponder) async -> T?,
                              completion: @escaping @MainActor (T?) -> Void,
                              cancellation: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        dispatchPrecondition(condition: .onQueue(.main))

        // cancel the decision making Task if WebView deallocates before it‘s finished
        let webViewDeinitObserver = webView.deinitObservers.insert(NSObject.DeinitObserver()).memberAfterInsert
        let webViewDebugRef = Unmanaged.passUnretained(webView).toOpaque().hexValue

        // TO DO: ideally the Task should be executed synchronously until the first await, check it later when custom Executors arrive to Swift
        let task = Task.detached { @MainActor [responders, weak webView, weak webViewDeinitObserver] in
            await withTaskCancellationHandler {
                for responder in responders {
                    // in case of the Task cancellation completion handler will be called in `onCancel:`
                    guard !Task.isCancelled else { return }
#if DEBUG
                    let longDecisionMakingCheckCancellable = Self.checkLongDecisionMaking(performedBy: responder) {
                        "<WKWebView: \(webViewDebugRef)>: " + actionDebugInfo.debugDescription
                    }
                    defer {
                        longDecisionMakingCheckCancellable?.cancel()
                    }
#endif
                    // complete if responder returns non-nil (non-`.next`) decision
                    if let decision = await decide(responder) {
                        guard !Task.isCancelled else { return }

                        completion(decision)
                        return
                    }
                }
                // default completion handler if none of responders returned non-nil result
                guard !Task.isCancelled else { return }
                completion(nil)

            } onCancel: {
                DispatchQueue.main.async {
                    cancellation()
                }
            }

            // remove WebView deallocation observer on the Task completion
            if let webViewDeinitObserver {
                webViewDeinitObserver.disarm()
                webView?.deinitObservers.remove(webViewDeinitObserver)
            }
        }

        // cancel the Task if WebView deallocates before it‘s finished
        webViewDeinitObserver.onDeinit { [log] in
            os_log("cancelling \(actionDebugInfo.debugDescription) decision making due to <WKWebView: \(webViewDebugRef)> deallocation", log: log, type: .error)
            task.cancel()
        }

        return task
    }
    // swiftlint:enable function_parameter_count

    func makeAsyncDecision<T>(for actionDebugInfo: some CustomDebugStringConvertible,
                              boundToLifetimeOf webView: WKWebView,
                              with responders: ResponderChain,
                              decide: @escaping @MainActor (NavigationResponder) async -> T?,
                              completion: @escaping @MainActor (T?) -> Void) {
        _=makeAsyncDecision(for: actionDebugInfo, boundToLifetimeOf: webView, with: responders, decide: decide, completion: completion, cancellation: { @MainActor in
            completion(nil)
        })
    }

#if DEBUG

    /// DEBUG check raising SIGINT (break) if NavigationResponder decision making takes more than 4 seconds
    /// the check won‘t be made if `responder.shouldDisableLongDecisionMakingChecks` returns `true`
    @MainActor
    static func checkLongDecisionMaking<Responder: NavigationResponder>(performedBy responder: Responder, debugDescription: @escaping () -> String) -> AnyCancellable? {
        let typeOfResponder = String(describing: Responder.self)
        var timeoutWorkItem: DispatchWorkItem?
        if !Self.sigIntRaisedForResponders.contains(typeOfResponder),
           // class-type responder will be queried for shouldDisableLongDecisionMakingChecks after delay
           (responder as? NavigationResponder & AnyObject) != nil
            // struct-type can‘t be mutated so it should have shouldDisableLongDecisionMakingChecks set permanently if its decisions take long
            || !responder.shouldDisableLongDecisionMakingChecks {

            let responder = responder as? NavigationResponder & AnyObject
            timeoutWorkItem = DispatchWorkItem { [weak responder] in
                guard responder?.shouldDisableLongDecisionMakingChecks != true else { return }
                Self.sigIntRaisedForResponders.insert(typeOfResponder)

                breakByRaisingSigInt("""
                    Decision making for \(debugDescription())
                    is taking longer than expected.
                    This may be indicating that there‘s a leak in \(typeOfResponder) Navigation Responder.

                    Implement `var shouldDisableLongDecisionMakingChecks: Bool` and set it to `true`
                    for known long decision making to disable this warning.
                """)
            }
        }
        if let timeoutWorkItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: timeoutWorkItem)
            return AnyCancellable {
                timeoutWorkItem.cancel()
            }
        }
        return nil
    }

#endif

    /// Instantiates a new Navigation object for a NavigationAction
    /// or returns an ExpectedNavigation instance for navigations initiated using Navigator
    /// or returns ongoing Navigation for server redirects
    /// Maps `WKNavigationAction` to `NavigationAction` according to an active server redirect or an expected NavigationType
    @MainActor
    func navigation(for wkNavigationAction: WKNavigationAction, in webView: WKWebView) -> Navigation? {
        guard wkNavigationAction.targetFrame?.isMainFrame == true else {
            return nil
        }
        // only handled for main-frame navigations:
        // get WKNavigation associated with the WKNavigationAction
        // it is not `current` yet, unless it‘s a server-redirect
#if _MAIN_FRAME_NAVIGATION_ENABLED
        let wkNavigation = wkNavigationAction.mainFrameNavigation
#else
        let wkNavigation = webView.expectedMainFrameNavigation(for: wkNavigationAction)
#endif
        let navigation: Navigation = {
            if let navigation = wkNavigation?.navigation {
                // same-document NavigationActions have a previous WKNavigation mainFrameNavigation
                // use the same Navigation for finished navigations (as they won‘t receive `didFinish`)
                // but create a new Navigation and client-redirect an old one for non-finished navigations
                if wkNavigationAction.isSameDocumentNavigation {
                    if navigation === startedNavigation, !navigation.state.isFinished {
                        navigation.willPerformClientRedirect(to: wkNavigationAction.request.url ?? .empty, delay: 0)
                    }
                    // continue to new Navigation object creation
                } else {
                    // it‘s a server-redirect or a developer-initiated navigation, so the WKNavigation already has an associated Navigation object
                    return navigation
                }

            // server-redirected navigation continues with the same WKNavigation identity
            } else if let startedNavigation,
                      case .started = startedNavigation.state,
                      // redirect Navigation Action should always have sourceFrame set:
                      // https://github.com/WebKit/WebKit/blob/c39358705b79ccf2da3b76a8be6334e7e3dfcfa6/Source/WebKit/UIProcess/WebPageProxy.cpp#L5675
                      wkNavigationAction.safeSourceFrame != nil,
                      wkNavigationAction.isRedirect != false {

                return startedNavigation
            }
            return Navigation(identity: NavigationIdentity(wkNavigation), responders: responders, state: .expected(nil), isCurrent: false)
        }()
        // wkNavigation.navigation = navigation
        if wkNavigation?.navigation == nil || wkNavigation?.navigation?.state.isFinished == true {
            navigation.associate(with: wkNavigation)
        }

        // custom NavigationType for navigations with developer-set NavigationType
        var navigationType: NavigationType? = navigation.state.expectedNavigationType
        var redirectHistory: [NavigationAction]?

        // server redirect received
        if startedNavigation === navigation {
            assert(navigationType == nil)
            navigationType = .redirect(.server)
            redirectHistory = navigation.navigationActions

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
    // swiftlint:disable function_body_length
    // swiftlint:disable cyclomatic_complexity
    public func webView(_ webView: WKWebView, decidePolicyFor wkNavigationAction: WKNavigationAction, preferences wkPreferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {

        // new navigation or an ongoing navigation (for a server-redirect)?
        let navigation = navigation(for: wkNavigationAction, in: webView)
        // extract WKNavigationAction mapped to NavigationAction from the Navigation or make new for non-main-frame Navigation Actions
        let navigationAction = navigation?.navigationAction
            ?? NavigationAction(webView: webView, navigationAction: wkNavigationAction, currentHistoryItemIdentity: currentHistoryItemIdentity, redirectHistory: nil, mainFrameNavigation: startedNavigation)
        // associate NavigationAction with WKNavigationAction object
        wkNavigationAction.navigationAction = navigationAction

        // only for MainFrame navigations: get currently ongoing (started) MainFrame Navigation
        // or Navigation object associated with the NavigationAction (weak)
        // it will be different from the Navigation we got above for same-document navigations
        let mainFrameNavigation = withExtendedLifetime(navigation) {
            navigationAction.isForMainFrame ? navigationAction.mainFrameNavigation : nil
        }
        // ensure the NavigationAction is added to the Navigation
        if let mainFrameNavigation, mainFrameNavigation.navigationActions.isEmpty {
            mainFrameNavigation.navigationActionReceived(navigationAction)
        }

        assert(navigationAction.mainFrameNavigation != nil || !navigationAction.isForMainFrame)
        os_log("decidePolicyFor: %s %s", log: log, type: .default, navigationAction.debugDescription, wkNavigationAction.mainFrameNavigation?.debugDescription ?? "")

        // initial `about:` scheme navigation doesn‘t wait for decision
        if (navigationAction.url.scheme.map(URL.NavigationalScheme.init) == .about
            && (webView.backForwardList.currentItem == nil || navigationAction.navigationType == .sessionRestoration))
            // same-document navigations do the same
            || wkNavigationAction.isSameDocumentNavigation && navigationAction.navigationType != .redirect(.server) {

            // allow them right away
            decisionHandler(.allow, wkPreferences)
            if let mainFrameNavigation, !mainFrameNavigation.isCurrent {
                self.willStart(mainFrameNavigation)
            }
            return
        }

        var preferences = NavigationPreferences(userAgent: webView.customUserAgent, preferences: wkPreferences)
        // keep WKNavigationAction alive until the decision is made but not any longer!
        var wkNavigationAction: WKNavigationAction! = wkNavigationAction
        // pass async decision making to Navigation.navigationResponders (or the delegate navigationResponders for non-main-frame navigations)
        let task = makeAsyncDecision(for: navigationAction, boundToLifetimeOf: webView, with: mainFrameNavigation?.navigationResponders ?? responders) { @MainActor responder in
            dispatchPrecondition(condition: .onQueue(.main))

            // get to next responder until we get non-nil (.next == nil) decision
            guard let decision = await responder.decidePolicy(for: navigationAction, preferences: &preferences) else { return .next }
            os_log("%s: %s decision: %s", log: self.log, type: .default, navigationAction.debugDescription, "\(type(of: responder))", decision.debugDescription)
            // pass non-nil decision to `completion:`
            return decision

        } completion: { @MainActor [self, weak webView] (decision: NavigationActionPolicy?) in
            dispatchPrecondition(condition: .onQueue(.main))
            guard let webView else {
                decisionHandler(.cancel, wkPreferences)
                return
            }

            switch decision {
            case .allow, .none:
                if let userAgent = preferences.userAgent {
                    webView.customUserAgent = userAgent
                }
                decisionHandler(.allow, preferences.applying(to: wkPreferences))

                if let mainFrameNavigation, !mainFrameNavigation.isCurrent {
                    // another navigation is starting
                    self.startedNavigation?.didResignCurrent()
                    guard case .navigationActionReceived = mainFrameNavigation.state else {
                        return // navigation cancelled
                    }
                    self.willStart(mainFrameNavigation)
                }

            case .cancel:
                decisionHandler(.cancel, wkPreferences)

                if mainFrameNavigation?.isCurrent != true {
                    self.didCancelNavigationAction(navigationAction, withRedirectNavigations: nil)
                }

            case .redirect(_, let redirect):
                assert(navigationAction.isForMainFrame)

                decisionHandler(.cancel, wkPreferences)
                var expectedNavigations = [ExpectedNavigation]()
                // run the `redirect` closure with a Navigator wrapper collecting all the ExpectedNavigations produced
                withUnsafeMutablePointer(to: &expectedNavigations) { expectedNavigationsPtr in
                    let navigator = webView.navigator(distributedNavigationDelegate: self, redirectedNavigation: mainFrameNavigation, expectedNavigations: expectedNavigationsPtr)
                    redirect(navigator)
                }
                // ignore already started Navigations (they will receive didFail)
                if mainFrameNavigation?.isCurrent != true {
                    didCancelNavigationAction(navigationAction, withRedirectNavigations: expectedNavigations)
                }

            case .download:
                self.willStartDownload(with: navigationAction, in: webView)
                decisionHandler(.downloadPolicy, wkPreferences)
            }
            // don‘t release the original WKNavigationAction until the end
            withExtendedLifetime(wkNavigationAction) {}

        } /* Task */ cancellation: {
            dispatchPrecondition(condition: .onQueue(.main))

            os_log("Task cancelled for %s", log: self.log, type: .default, navigationAction.debugDescription)
            decisionHandler(.cancel, wkPreferences)

            // in case decision making is hung release WKNavigationAction just after cancellation
            // to release WKProcessPool and everything bound to it including UserContentController
            withExtendedLifetime(wkNavigationAction) {}
            wkNavigationAction = nil
        }

        if navigationAction.isForMainFrame {
            // cancel previous `decidePolicyForNavigationAction` async operations when new Navigation begins
            self.navigationActionDecisionTask = task
        }
    }
    // swiftlint:enable function_body_length
    // swiftlint:enable cyclomatic_complexity

    @MainActor
    private func willStart(_ navigation: Navigation) {
        os_log("willStart %s", log: log, type: .default, navigation.debugDescription)

        var isSameDocumentNavigation: Bool {
            guard startedNavigation !== navigation && startedNavigation?.url.isSameDocument(navigation.url) == true else { return false }
#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
            return navigation.navigationAction.navigationType == .sameDocumentNavigation(.anchorNavigation)
#else
            return navigation.navigationAction.navigationType == .sameDocumentNavigation
#endif
        }
        if navigation.navigationAction.navigationType.redirect?.isClient == true // is client redirect?
            // is same document navigation received as client redirect?
            || isSameDocumentNavigation {

            // notify the original (redirected) Navigation about the redirect NavigationAction received
            // this should call the overriden ResponderChain inside `willPerformClientRedirect`
            // that in turn notifies the original responders and finishes the Navigation
            startedNavigation?.didPerformClientRedirect(with: navigation.navigationAction)
        }

        navigation.willStart()
        for responder in navigation.navigationResponders {
            responder.willStart(navigation)
        }
        // same-document navigations won‘t receive didStartProvisionalNavigation, so change the state here
        if navigation.navigationAction.navigationType.isSameDocumentNavigation {
            navigation.started(nil)
            startedNavigation = navigation
            navigationExpectedToStart = nil
        } else {
            navigationExpectedToStart = navigation
        }
    }

    @MainActor
    private func willStartDownload(with navigationAction: NavigationAction, in webView: WKWebView) {
        let responders = (navigationAction.isForMainFrame ? navigationAction.mainFrameNavigation?.navigationResponders : nil) ?? responders
        for responder in responders {
            responder.navigationAction(navigationAction, willBecomeDownloadIn: webView)
        }
    }

    @MainActor
    private func didCancelNavigationAction(_ navigationAction: NavigationAction, withRedirectNavigations expectedNavigations: [ExpectedNavigation]?) {
        let responders = (navigationAction.isForMainFrame ? navigationAction.mainFrameNavigation?.navigationResponders : nil) ?? responders
        for responder in responders {
            responder.didCancelNavigationAction(navigationAction, withRedirectNavigations: expectedNavigations)
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

        os_log("didReceive challenge: %s: %s", log: log, type: .default, navigation?.debugDescription ?? webView.debugDescription, challenge.protectionSpace.description)

        makeAsyncDecision(for: navigation?.debugDescription ?? challenge.debugDescription, boundToLifetimeOf: webView, with: navigation?.navigationResponders ?? responders) { @MainActor responder in
            dispatchPrecondition(condition: .onQueue(.main))

            guard let decision = await responder.didReceive(challenge, for: navigation) else { return .next }
            os_log("%s: %s decision: %s", log: self.log, type: .default, String(describing: challenge), "\(type(of: responder))", decision.description)

            return decision

        } completion: { @MainActor [self] (decision: AuthChallengeDisposition?) in
            dispatchPrecondition(condition: .onQueue(.main))

            guard let (disposition, credential) = decision?.dispositionAndCredential else {
                os_log("%s: performDefaultHandling", log: self.log, type: .default, String(describing: challenge))
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
        os_log("didReceiveServerRedirect %s for: %s", log: log, type: .default, navigation.navigationAction.debugDescription, navigation.debugDescription)

        for responder in navigation.navigationResponders {
            responder.didReceiveRedirect(navigation.navigationAction, for: navigation)
        }
    }

    // MARK: Navigation

    @MainActor
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation wkNavigation: WKNavigation?) {
        var navigation: Navigation

        lazy var finishedNavigationAction: NavigationAction? = {
            guard let navigation = wkNavigation?.navigation else { return nil }
            if navigation.isCompleted, navigation.hasReceivedNavigationAction {
                // about: scheme navigation for `<a target='_blank'>` duplicates didStart/didCommit/didFinish events with the same WKNavigation
                return navigation.navigationAction
            } else {
                // we‘ll get here when allowing to open a new window with an empty URL (`window.open()`) from a permission context menu
                return nil
            }
        }()

        if let approvedNavigation = wkNavigation?.navigation,
           approvedNavigation.state == .approved, approvedNavigation.hasReceivedNavigationAction {
            // rely on the associated Navigation that is in the correct state
            navigation = approvedNavigation

        } else if let expectedNavigation = navigationExpectedToStart,
                  wkNavigation != nil
                    || expectedNavigation.navigationAction.navigationType == .sessionRestoration
                    || expectedNavigation.navigationAction.url.navigationalScheme == .about {

            // regular flow: start .expected navigation
            navigation = expectedNavigation

        } else {
            // make a new Navigation object for unexpected navigations (that didn‘t receive corresponding `decidePolicyForNavigationAction`)
            navigation = Navigation(identity: NavigationIdentity(wkNavigation), responders: responders, state: .expected(nil), isCurrent: true)

            let navigationAction: NavigationAction = {
                if wkNavigation == nil, webView.url?.isEmpty == false {
                    // loading error page
                    return .alternateHtmlLoadNavigation(webView: webView, mainFrameNavigation: navigation)
                }
                return NavigationAction(request: URLRequest(url: webView.url ?? .empty),
                                        navigationType: finishedNavigationAction?.navigationType ?? .other,
                                        currentHistoryItemIdentity: nil,
                                        redirectHistory: nil,
                                        isUserInitiated: false,
                                        sourceFrame: finishedNavigationAction?.sourceFrame ?? .mainFrame(for: webView),
                                        targetFrame: finishedNavigationAction?.targetFrame ?? .mainFrame(for: webView),
                                        shouldDownload: false,
                                        mainFrameNavigation: navigation)
            }()
            navigation.navigationActionReceived(navigationAction)
            navigation.willStart()
        }

        navigation.started(wkNavigation)
        self.startedNavigation = navigation
        self.navigationExpectedToStart = nil

        os_log("didStart: %s", log: log, type: .default, navigation.debugDescription)
        assert(navigation.navigationAction.navigationType.redirect != .server, "server redirects shouldn‘t call didStartProvisionalNavigation")

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

        os_log("decidePolicyFor: %s", log: log, type: .default, navigationResponse.debugDescription)

        let responders = (navigationResponse.isForMainFrame ? startedNavigation?.navigationResponders : nil) ?? responders
        makeAsyncDecision(for: navigationResponse.debugDescription, boundToLifetimeOf: webView, with: responders) { @MainActor responder in
            dispatchPrecondition(condition: .onQueue(.main))

            guard let decision = await responder.decidePolicy(for: navigationResponse) else { return .next }
            os_log("%s: %s decision: %s", log: self.log, type: .default, navigationResponse.debugDescription, "\(type(of: responder))", "\(decision)")

            return decision

        } completion: { @MainActor [weak self, weak webView] (decision: NavigationResponsePolicy?) in
            dispatchPrecondition(condition: .onQueue(.main))
            guard let webView else {
                decisionHandler(.cancel)
                return
            }

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

        os_log("willPerformClientRedirect to: %s, current: %s", log: log, type: .default, url.absoluteString, redirectedNavigation.debugDescription)

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
        os_log("webViewDidCancelClientRedirect", log: log, type: .default)

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
            os_log("dropping didFinishNavigation: %s, as another navigation is active: %s", log: log, type: .default, wkNavigation?.description ?? "<nil>", navigation?.debugDescription ?? "<nil>")
            return
        }

#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
        updateCurrentHistoryItemIdentity(webView.backForwardList.currentItem)
#endif
        navigation.didFinish(wkNavigation)
        os_log("didFinish: %s", log: log, type: .default, navigation.debugDescription)

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
            os_log("dropping didFail%sNavigation: %s with: %s, as another navigation is active: %s", log: log, type: .default, isProvisional ? "Provisional" : "", wkNavigation?.description ?? "<nil>", error.errorDescription ?? error.localizedDescription, navigation?.debugDescription ?? "<nil>")
            return
        }

#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
        updateCurrentHistoryItemIdentity(webView.backForwardList.currentItem)
#endif

        if navigation.isCurrent && !isProvisional {
            navigation.didResignCurrent()
        }
        navigation.didFail(wkNavigation, with: error)
        os_log("didFail %s: %s", log: log, type: .default, navigation.debugDescription, error.errorDescription ?? error.localizedDescription)

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

#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
    @MainActor
    @objc(_webView:navigation:didSameDocumentNavigation:)
    public func webView(_ webView: WKWebView, wkNavigation: WKNavigation?, didSameDocumentNavigation wkNavigationType: Int) {
        // currentHistoryItemIdentity should only change for completed navigation, not while in progress
        let navigationType = WKSameDocumentNavigationType(rawValue: wkNavigationType) ?? {
            assertionFailure("Unsupported SameDocumentNavigationType \(wkNavigationType)")
            return .anchorNavigation
        }()

        //
        // Anchor navigations are using the original WKNavigation object that was used to load current document,
        //   but its `.request` will contain an updated URL with a #fragment.
        //
        // - These navigations go through the standard `decidePolicyFor` and `willStart` sequence and stored
        //   in the `startedNavigation` var. Such navigations have their `isCurrent` flag set.
        // - In case of Anchor navigations there‘s a preceding State Pop event received, it‘s probably used
        //   to manage navigation history and is not really of our interest.
        //   Those navigations won‘t have `isCurrent` flag set (see below)
        //
        // Session State push/replace/pop navigations don‘t receive `decidePolicyFor` but their WKNavigation (new one) contains a valid request.
        //
        // - In case of a Session State Pop navigation, an additional Anchor Navigation event will be received.
        //   Its WKNavigation is set to the original document load navigation (finished long before).
        //   Such navigations have `isCurrent` unset when the original document has loaded allowing us to distinguish
        //   the real State Pop events
        //
        let navigation: Navigation
        if let associatedNavigation = wkNavigation?.navigation {
            // Anchor navigations will have an associated Navigation set in `decidePolicyFor`
            if let startedNavigation, startedNavigation.identity == associatedNavigation.identity {
                // client-redirect to the same document - same WKNavigation (identity) is used for different Navigation object
                // so instead use `startedNavigation` set in `willStart`
                navigation = startedNavigation
            } else {
                navigation = associatedNavigation
            }
            // mark Navigation as finished as we‘re in __did__SameDocumentNavigation
            // if we‘ve got the main-document load Navigation (which may be the case) - we don‘t want to finish it here.
            if navigation.isCurrent, navigation.navigationAction.navigationType.isSameDocumentNavigation, !navigation.isCompleted {
                navigation.didFinish()
            }

        } else {
            let shouldBecomeCurrent = {
                guard let startedNavigation else { return true } // no current navigation, make the same-doc navigation current
                guard startedNavigation.navigationAction.navigationType.isSameDocumentNavigation else { return false } // don‘t intrude into current non-same-doc navigation
                // don‘t mark extra Session State Pop navigations as `current` when there‘s a `current` same-doc Anchor navigation stored in `startedNavigation`
                return !startedNavigation.isCurrent
            }()

            navigation = Navigation(identity: NavigationIdentity(wkNavigation), responders: responders, state: .expected(nil), isCurrent: shouldBecomeCurrent)
            let request = wkNavigation?.request ?? URLRequest(url: webView.url ?? .empty)
            let navigationAction = NavigationAction(request: request, navigationType: .sameDocumentNavigation(navigationType), currentHistoryItemIdentity: currentHistoryItemIdentity, redirectHistory: nil, isUserInitiated: wkNavigation?.isUserInitiated ?? false, sourceFrame: .mainFrame(for: webView), targetFrame: .mainFrame(for: webView), shouldDownload: false, mainFrameNavigation: navigation)
            navigation.navigationActionReceived(navigationAction)
            os_log("new same-doc navigation(.%d): %s (%s): %s, isCurrent: %d", log: log, type: .debug, wkNavigationType, wkNavigation.debugDescription, navigation.debugDescription, navigationAction.debugDescription, shouldBecomeCurrent ? 1 : 0)

            // store `current` navigations in `startedNavigation` to get `currentNavigation` published
            if shouldBecomeCurrent {
                self.startedNavigation = navigation
            }
            // mark Navigation as finished as we‘re in __did__SameDocumentNavigation
            navigation.didFinish()
        }

        os_log("didSameDocumentNavigation: %s.%s: %s", log: log, type: .default, wkNavigation.debugDescription, navigationType.debugDescription, navigation.debugDescription)

        for responder in responders {
            responder.navigation(navigation, didSameDocumentNavigationOf: navigationType)
        }

        // same as above, main-document load navigations sometimes passed to this method shouldn‘t have `isCurrent` unset
        if navigation.navigationAction.navigationType.isSameDocumentNavigation {
            if self.startedNavigation === navigation {
                self.startedNavigation = nil // will call `didResignCurrent`
            } else {
                navigation.didResignCurrent()
            }
        }

        updateCurrentHistoryItemIdentity(webView.backForwardList.currentItem)
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
#endif

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
            assert(wkNavigation == nil, "Unexpected didCommitNavigation without preceding didStart")
            return
        }
#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
        updateCurrentHistoryItemIdentity(webView.backForwardList.currentItem)
#endif
        navigation.committed(wkNavigation)
        os_log("didCommit: %s", log: log, type: .default, navigation.debugDescription)

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
        os_log("navigationActionDidBecomeDownload: %s", log: log, type: .default, navigationAction.debugDescription)

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
        os_log("navigationResponseDidBecomeDownload: %s", log: log, type: .default, navigationResponse.debugDescription)

        let responders = (navigationResponse.isForMainFrame ? navigationResponse.mainFrameNavigation?.navigationResponders : nil) ?? responders
        for responder in responders {
            responder.navigationResponse(navigationResponse, didBecome: download)
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
        os_log("%s webContentProcessDidTerminateWithReason: %d", log: log, type: .default, webView.debugDescription, reason?.rawValue ?? -1)

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
