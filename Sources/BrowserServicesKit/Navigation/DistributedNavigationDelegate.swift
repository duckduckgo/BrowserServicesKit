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

    private var expectedNavigationAction: (navigationType: NavigationType?, url: URL?)?

    @Published
    public private(set) var currentNavigation: Navigation?

    public init(logger: OSLog) {
        self.logger = logger
    }

    public func setResponders(_ refs: ResponderRefMaker?...) {
        let nonnullRefs = refs.compactMap { $0 }
        responderRefs = nonnullRefs.map(\.ref)
        assert(responders.count == nonnullRefs.count, "Some NavigationResponders were released right after adding: "
               + "\(Set(nonnullRefs.map(\.ref.responderType)).subtracting(responders.map { "\(type(of: $0))" }))")
    }

    public func setExpectedNavigationType(_ navigationType: NavigationType, for url: URL? = nil) {
        expectedNavigationAction = (navigationType, url)
    }

}

private extension DistributedNavigationDelegate {

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

    func getBackForwardNavigationDistanceFromCurrentItem(in webView: WKWebView) -> Int? {
        // calculate backForwardNavigationDistance for back/forward navigations
        guard case .backForward(from: .some(let fromItem)) = currentNavigation?.navigationAction.navigationType else { return nil }

        if let forwardIndex = webView.backForwardList.forwardList.firstIndex(where: { HistoryItemIdentity($0) == fromItem }) {
            return -forwardIndex - 1 // going back from item in forward list to current, zero based index
        } else if let backIndex = webView.backForwardList.backList.firstIndex(where: { HistoryItemIdentity($0) == fromItem }) {
            return backIndex + 1  // going forward from item in back list to current, zero based index
        }
        return nil
    }

    func navigationAction(for navigationAction: WKNavigationAction, in webView: WKWebView) -> NavigationAction {
        guard let url = navigationAction.request.url,
              navigationAction.targetFrame?.isMainFrame == true
        else {
            return NavigationAction(webView: webView, navigationAction: navigationAction)
        }

        let navigationType: NavigationType?
        if let expected = expectedNavigationAction,
           expected.url == nil || expected.url?.matches(url) == true {
            // client-defined expected navigation type matching current main frame navigation URL
            navigationType = expected.navigationType
            expectedNavigationAction = nil

        } else if navigationAction.navigationType != .other || navigationAction.isUserInitiated {
            // this is a user-initiated navigation action, not a redirect
            navigationType = nil

        } else if var currentNavigation, let redirectType = currentNavigation.redirectType(for: url) {
            // current navigation is in redirect-expecting state
            navigationType = .redirect(type: redirectType,
                                       history: (currentNavigation.navigationAction.navigationType.redirectHistory ?? []) + [url],
                                       initial: InitialNavigationType(navigationType: currentNavigation.navigationAction.navigationType))
            currentNavigation.redirected()
            self.currentNavigation = currentNavigation
        } else {
            navigationType = nil // resolve from WKNavigationAction navigation type
        }

        return NavigationAction(webView: webView, navigationAction: navigationAction, navigationType: navigationType)
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

            switch decision {
            case .allow, .none:
                self.willStart(navigationAction)
                webView.customUserAgent = preferences.userAgent
                decisionHandler(.allow, preferences.applying(to: wkPreferences))

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

        if let currentNavigation, case .awaitingFinishOrClientRedirect = currentNavigation.state {
            // when starting a new (non-redirect) navigation and `didFinish` wasn‘t called for the old one
            reallyFinishNavigation(currentNavigation)
        }

        currentNavigation = .expected(navigationAction: navigationAction, current: currentNavigation)
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

    // MARK: Navigation

    @MainActor
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation wkNavigation: WKNavigation?) {
        let navigation: Navigation
        if var currentNavigation, let wkNavigation {
            // regular flow: start .expected navigation
            currentNavigation.started(wkNavigation, backForwardNavigationDistance: getBackForwardNavigationDistanceFromCurrentItem(in: webView))
            navigation = currentNavigation

        } else {
            // session restoration happens without NavigationAction
            navigation = .started(navigationAction: .sessionRestoreNavigation(webView: webView), navigation: wkNavigation)
        }
        currentNavigation = navigation
        os_log("didStart: %s", log: logger, type: .default, navigation.debugDescription)
        assert(navigation.navigationAction.navigationType.redirectType != .server, "server redirects shouldn‘t call didStartProvisionalNavigation")

        for responder in responders {
            responder.didStart(navigation)
        }
    }

    @MainActor
    public func webView(_ webView: WKWebView,
                        didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        os_log("didReceive challenge: %s: %s", log: logger, type: .default, currentNavigation?.debugDescription ?? webView.debugDescription, String(describing: challenge))

        makeAsyncDecision { responder in
            guard let decision = await responder.didReceive(challenge) else { return .next }
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
    public func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation?) {
        assert(currentNavigation != nil)
        currentNavigation?.didReceiveServerRedirect(for: navigation)
        os_log("didReceiveServerRedirect for: %s", log: logger, type: .default, currentNavigation?.debugDescription ?? "<nil>")
    }

    @MainActor
    public func webView(_ webView: WKWebView, decidePolicyFor wkNavigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let navigationResponse = NavigationResponse(navigationResponse: wkNavigationResponse)
        if wkNavigationResponse.isForMainFrame {
            assert(currentNavigation != nil)
            currentNavigation?.receivedResponse(navigationResponse)
        }

        os_log("decidePolicyFor response: %s", log: logger, type: .default, navigationResponse.debugDescription)

        makeAsyncDecision { [currentNavigation] responder in
            guard let decision = await responder.decidePolicy(for: navigationResponse, currentNavigation: currentNavigation) else { return .next }
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
        currentNavigation?.committed(navigation)
        guard let currentNavigation else {
            assertionFailure("Unexpected didCommitNavigation")
            return
        }
        os_log("didCommit: %s", log: logger, type: .default, currentNavigation.debugDescription)

        for responder in responders {
            responder.didCommit(currentNavigation)
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

        os_log("willPerformClientRedirect to: %s", log: logger, type: .default, url.absoluteString)
        currentNavigation?.willPerformClientRedirect(to: url, delay: delay)
    }
#endif

    // MARK: Completion

    @MainActor
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        currentNavigation?.willFinish(navigation)
        guard let currentNavigation = currentNavigation else {
            assertionFailure("Unexpected didFinishNavigation")
            return
        }
        os_log("didFinishOrRedirected: %s", log: logger, type: .default, currentNavigation.debugDescription)

        for responder in responders {
            responder.navigationWillFinishOrRedirect(currentNavigation)
        }

        // Shortly after receiving webView:didFinishNavigation: a client redirect navigation may start
        // it should happen before the evaluateJS callback happens
        webView.evaluateJavaScript("") { [weak self, navigation=currentNavigation] _, _ in
            self?.reallyFinishNavigation(navigation)
        }
    }

    @MainActor
    private func reallyFinishNavigation(_ finishingNavigation: Navigation) {
        guard currentNavigation == finishingNavigation else {
            // don‘t finish if current navigation state has changed (i.e. redirected)
            return
        }
        var finishingNavigation = finishingNavigation
        finishingNavigation.didFinish()
        os_log("didFinish: %s", log: self.logger, type: .default, finishingNavigation.debugDescription)

        self.currentNavigation = finishingNavigation
        for responder in responders {
            responder.navigationDidFinish(finishingNavigation)
        }
        self.currentNavigation = nil
    }

    @MainActor
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        let error = error as? WKError ?? WKError(_nsError: error as NSError)
        currentNavigation?.didFail(navigation, with: error)

        guard let currentNavigation else {
            assertionFailure("Unexpected navigationDidFail")
            return
        }
        os_log("didFail %s: %s", log: logger, type: .default, currentNavigation.debugDescription, error.localizedDescription)

        for responder in responders {
            responder.navigation(currentNavigation, didFailWith: error, isProvisioned: false)
        }
        self.currentNavigation = nil
    }

    @MainActor
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
        let error = error as? WKError ?? WKError(_nsError: error as NSError)
        currentNavigation?.didFail(navigation, with: error)

        guard let currentNavigation else {
            assertionFailure("Unexpected navigationDidFail")
            return
        }
        os_log("didFail provisional %s: %s", log: logger, type: .default, currentNavigation.debugDescription, error.localizedDescription)

        for responder in responders {
            responder.navigation(currentNavigation, didFailWith: error, isProvisioned: true)
        }
        self.currentNavigation = nil
    }

    @MainActor
    @available(macOS 11.3, iOS 14.5, *) // objc does‘t care about availability
    @objc(webView:navigationAction:didBecomeDownload:)
    public func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        let navigationAction = NavigationAction(webView: webView, navigationAction: navigationAction)
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
            responder.navigationResponse(navigationResponse, didBecome: download, currentNavigation: currentNavigation)
        }
        if navigationResponse.isForMainFrame {
            currentNavigation = nil
        }
    }

    @MainActor
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        currentNavigation?.didFail(with: WKError(WKError.Code.webContentProcessTerminated))
        os_log("%s process did terminate; current navigation: %s", log: logger, type: .default, webView.debugDescription, currentNavigation?.debugDescription ?? "<nil>")

        for responder in responders {
            responder.webContentProcessDidTerminate(currentNavigation: currentNavigation)
        }
        currentNavigation = nil
    }

}

// MARK: - Responders
extension DistributedNavigationDelegate {

    fileprivate enum ResponderRef<T: NavigationResponder>: AnyResponderRef {
        case weak(WeakResponderRef<T>)
        case strong(T)
        var responder: NavigationResponder? {
            switch self {
            case .weak(let ref): return ref.responder
            case .strong(let responder): return responder
            }
        }
        var responderType: String {
            "\(T.self)"
        }
    }

    public struct ResponderRefMaker {
        fileprivate let ref: AnyResponderRef
        private init(_ ref: AnyResponderRef) {
            self.ref = ref
        }
        public static func `weak`(_ responder: (some NavigationResponder & AnyObject)) -> ResponderRefMaker {
            return .init(ResponderRef.weak(WeakResponderRef(responder)))
        }
        public static func `weak`(nullable responder: (some NavigationResponder & AnyObject)?) -> ResponderRefMaker? {
            guard let responder = responder else { return nil }
            return .init(ResponderRef.weak(WeakResponderRef(responder)))
        }
        public static func `strong`(_ responder: some NavigationResponder & AnyObject) -> ResponderRefMaker {
            return .init(ResponderRef.strong(responder))
        }
        public static func `strong`(nulable responder: (some NavigationResponder & AnyObject)?) -> ResponderRefMaker? {
            guard let responder = responder else { return nil }
            return .init(ResponderRef.strong(responder))
        }
        public static func `struct`(_ responder: some NavigationResponder) -> ResponderRefMaker {
            assert(Mirror(reflecting: responder).displayStyle == .struct, "\(type(of: responder)) is not a struct")
            return .init(ResponderRef.strong(responder))
        }
        public static func `struct`(nullable responder: NavigationResponder?) -> ResponderRefMaker? {
            guard let responder = responder else { return nil }
            return .struct(responder)
        }
    }

    fileprivate final class WeakResponderRef<T: NavigationResponder> {
        weak var responder: (NavigationResponder & AnyObject)?
        init(responder: (NavigationResponder & AnyObject)?) {
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

extension DistributedNavigationDelegate.WeakResponderRef where T: AnyObject {
    convenience init(_ responder: T) {
        self.init(responder: responder)
    }
}
