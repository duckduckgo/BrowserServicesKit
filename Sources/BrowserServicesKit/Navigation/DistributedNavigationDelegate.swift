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

import Foundation
import WebKit
import os.log
import Common

final public class DistributedNavigationDelegate: DistributedWKNavigationDelegate {

    public func setResponders(_ refs: ResponderRefMaker?...) {
        let nonnullRefs = refs.compactMap { $0 }
        responderRefs = nonnullRefs.map(\.ref)
        assert(responders.count == nonnullRefs.count, "Some NavigationResponders were released right after adding: "
               + "\(Set(nonnullRefs.map(\.ref.responderType)).subtracting(responders.map { "\(type(of: $0))" }))")
    }

    public func setExpectedNavigationType(_ navigationType: NavigationType, for url: URL? = nil) {
        self.expectedNavigationAction = (navigationType, url)
    }

}

public class DistributedWKNavigationDelegate: NSObject {

    fileprivate final var responderRefs: [AnyResponderRef] = []
    fileprivate final var customDelegateMethodHandlers = [Selector: AnyResponderRef]()
    fileprivate final let logger: OSLog

    fileprivate final var expectedNavigationAction: (navigationType: NavigationType?, url: URL?)?
    public fileprivate(set) final var currentNavigation: Navigation?

    public required init(logger: OSLog) {
        self.logger = logger
    }

    fileprivate final func navigationAction(for navigationAction: WKNavigationAction) -> NavigationAction {
        guard navigationAction.targetFrame?.isMainFrame == true
        else {
            return NavigationAction(navigationAction)
        }

        let navigationType: NavigationType?
        if let expected = expectedNavigationAction,
           expected.url == nil || expected.url?.matches(navigationAction.request.url!) == true {
            // client-defined expected navigation type matching current main frame navigation URL
            navigationType = expected.navigationType
            expectedNavigationAction = nil
            
        } else if navigationAction.navigationType != .other || navigationAction.isUserInitiated {
            // this is a user-initiated navigation action, not a redirect
            navigationType = nil

        } else if let currentNavigation, let redirectType = currentNavigation.redirectType(for: navigationAction) {
            // current navigation is in redirect-expecting state
            currentNavigation.redirected()
            navigationType = .redirect(type: redirectType, previousNavigation: currentNavigation)

        } else {
            navigationType = nil // resolve from WKNavigationAction navigation type
        }

        return NavigationAction(navigationAction, navigationType: navigationType)
    }

}

private extension DistributedWKNavigationDelegate {

    private final func makeAsyncDecision<T>(decide: @escaping (NavigationResponder) async -> T?,
                                            completion: @escaping (T) -> Void,
                                            defaultHandler: @escaping () -> Void) {
        Task { @MainActor in
            var result: T?
            for responder in responders {
                guard let decision = await decide(responder) else { continue }
                result = decision
                break
            }
            if let result {
                completion(result)
            } else {
                defaultHandler()
            }
        }
    }

}

// MARK: - WebView Navigation Delegate
extension DistributedWKNavigationDelegate: WKNavigationDelegate {

    // MARK: Policy making
    @MainActor
    public func webView(_ webView: WKWebView, decidePolicyFor wkNavigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {

        let navigationAction = self.navigationAction(for: wkNavigationAction)
        os_log("%s decidePolicyFor: %s", log: logger, type: .default, webView.debugDescription, navigationAction.debugDescription)

        let decisionHandler = { (decision: WKNavigationActionPolicy, navigationPreferences: NavigationPreferences) in
            if case .allow = decision {
                if navigationAction.isForMainFrame {
                    webView.customUserAgent = navigationPreferences.userAgent
                }
                navigationPreferences.export(to: preferences)
            }
            decisionHandler(decision, preferences)
        }

        var preferences = NavigationPreferences(userAgent: webView.customUserAgent, preferences: preferences)

        makeAsyncDecision { responder in
            dispatchPrecondition(condition: .onQueue(.main))

            guard !Task.isCancelled else {
                os_log("%s: cancelling because of Task cancellation", log: self.logger, type: .default, navigationAction.debugDescription)
                return .cancel(with: .taskCancelled)
            }
            guard let decision = await responder.decidePolicy(for: navigationAction, preferences: &preferences) else { return .next }
            os_log("%s: %s decision: %s", log: self.logger, type: .default, navigationAction.debugDescription, "\(type(of: responder))", decision.debugDescription)

            return decision

        } completion: { (decision: NavigationActionPolicy) in
            dispatchPrecondition(condition: .onQueue(.main))

            switch decision {
            case .allow:
                self.willStart(navigationAction)
                decisionHandler(.allow, preferences)
            case .cancel(let relatedAction):
                self.willCancel(navigationAction, with: relatedAction)
                decisionHandler(.cancel, preferences)
                self.didCancel(navigationAction, with: relatedAction)
            case .download:
                decisionHandler(.download, preferences)
            }

        } defaultHandler: {
            self.willStart(navigationAction)
            decisionHandler(.allow, preferences)
        }
    }

    @MainActor
    private func willStart(_ navigationAction: NavigationAction) {
        os_log("will start %s", log: self.logger, type: .default, navigationAction.debugDescription)
        guard navigationAction.isForMainFrame else { return }

        self.currentNavigation = .expected(navigationAction: navigationAction, current: currentNavigation)
        for responder in responders {
            responder.willStart(navigationAction)
        }
    }

    @MainActor
    private func willCancel(_ navigationAction: NavigationAction, with relatedAction: NavigationActionCancellationRelatedAction) {
        os_log("will cancel %s with %s", log: self.logger, type: .default, navigationAction.debugDescription, relatedAction.debugDescription)
        guard navigationAction.isForMainFrame else { return }

        for responder in responders {
            responder.willCancel(navigationAction, with: relatedAction)
        }
    }

    @MainActor
    private func didCancel(_ navigationAction: NavigationAction, with relatedAction: NavigationActionCancellationRelatedAction) {
        guard navigationAction.isForMainFrame else { return }

        for responder in responders {
            responder.didCancel(navigationAction, with: relatedAction)
        }
    }

    @MainActor
    public func webView(_ webView: WKWebView,
                        didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        os_log("%s didReceive: %s", log: logger, type: .default, webView.debugDescription, String(describing: challenge))

        makeAsyncDecision { responder in
            guard let decision = await responder.didReceive(challenge) else { return .next }
            os_log("%s: %s decision: %s", log: self.logger, type: .default, String(describing: challenge), "\(type(of: responder))", String(describing: decision.dispositionAndCredential.0/*disposition*/))

            return decision

        } completion: { (decision: AuthChallengeDisposition) in
            let (disposition, credential) = decision.dispositionAndCredential
            os_log("%s didReceive: %s", log: self.logger, type: .default, webView.debugDescription, String(describing: challenge))
            completionHandler(disposition, credential)

        } defaultHandler: {
            os_log("%s: performDefaultHandling", log: self.logger, type: .default, String(describing: challenge))
            completionHandler(.performDefaultHandling, nil)
        }
    }

    // MARK: Navigation

    @MainActor
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation wkNavigation: WKNavigation?) {
        let navigation: Navigation
        if let currentNavigation, let wkNavigation {
            // regular flow
            currentNavigation.started(wkNavigation)
            navigation = currentNavigation

        } else if let url = webView.url {
            // session restoration happens without NavigationAction
            navigation = .started(navigationAction: .sessionRestoreNavigation(url: url), navigation: wkNavigation)
            currentNavigation = navigation

        } else {
            assertionFailure("didStartProvisionalNavigation without URL")
            return
        }
        os_log("%s didStart: %s", log: self.logger, type: .default, webView.debugDescription, currentNavigation!.debugDescription)

        for responder in responders {
            responder.didStart(navigation)
        }
    }

    @MainActor
    public func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation?) {
        assert(currentNavigation != nil)
        currentNavigation?.didReceiveServerRedirect(navigation: navigation)
        os_log("%s didReceiveServerRedirect for: %s", log: self.logger, type: .default, webView.debugDescription, currentNavigation?.debugDescription ?? "<nil>")
    }

    @MainActor
    public func webView(_ webView: WKWebView, decidePolicyFor wkNavigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if wkNavigationResponse.isForMainFrame {
            assert(currentNavigation != nil)
            currentNavigation?.receivedResponse(wkNavigationResponse.response)
        }

        let navigationResponse = NavigationResponse(navigationResponse: wkNavigationResponse, navigation: self.currentNavigation)
        os_log("%s decidePolicyFor: %s", log: logger, type: .default, webView.debugDescription, navigationResponse.debugDescription)

        makeAsyncDecision { responder -> NavigationResponsePolicy? in
            guard let decision = await responder.decidePolicy(for: navigationResponse) else { return .next }
            os_log("%s: %s decision: %s", log: self.logger, type: .default, navigationResponse.debugDescription, "\(type(of: responder))", "\(decision)")
            return decision
        } completion: { (decision: NavigationResponsePolicy) in
            switch decision {
            case .allow:
                decisionHandler(.allow)
            case .cancel:
                decisionHandler(.cancel)
            case .download:
                decisionHandler(.download)
            }
        } defaultHandler: {
            decisionHandler(.allow)
        }
    }

    @MainActor
    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) {
        guard let currentNavigation else {
            assertionFailure("Unexpected didCommitNavigation")
            return
        }
        assert(currentNavigation.matches(navigation))

        currentNavigation.committed()
        os_log("%s didCommit: %s", log: self.logger, type: .default, webView.debugDescription, currentNavigation.debugDescription)

        for responder in responders {
            responder.didCommit(currentNavigation)
        }
    }

#if WILLPERFORMCLIENTREDIRECT_ENABLED
    @MainActor
    @objc(_webView:willPerformClientRedirectToURL:delay:)
    public func webView(_ webView: WKWebView, willPerformClientRedirectTo url: URL, delay: TimeInterval) {
        if let forwardingTarget = self.forwardingTarget(for: #selector(webView(_:willPerformClientRedirectTo:delay:))) {
            withUnsafePointer(to: forwardingTarget) { $0.withMemoryRebound(to: DistributedNavigationDelegate?.self, capacity: 1) { $0 } }.pointee!
                .webView(webView, willPerformClientRedirectTo: url, delay: delay)
            return
        }
        guard let currentNavigation else {
            assertionFailure("Unexpected willPerformClientRedirectToURL")
            return
        }

        os_log("%s willPerformClientRedirect to: %s", log: self.logger, type: .default, webView.debugDescription, url.absoluteString)
        currentNavigation.willPerformClientRedirect(to: url, delay: delay)
    }
#endif

    @MainActor
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        guard let currentNavigation = currentNavigation else {
            assertionFailure("Unexpected didFinishNavigation")
            return
        }
        assert(currentNavigation.matches(navigation))
        currentNavigation.willFinish()
        os_log("%s did finish navigation or received client redirect: %s", log: self.logger, type: .default, webView.debugDescription, currentNavigation.debugDescription)

        for responder in responders {
            responder.navigationWillFinishOrRedirect(currentNavigation)
        }

        // Shortly after receiving webView:didFinishNavigation: a client redirect navigation may start
        // it should happen before the evaluateJS callback happens
        webView.evaluateJavaScript("") { [weak self, navigation=currentNavigation] _, _ in
            self?.reallyFinishNavigation(navigation, webView: webView)
        }
    }

    @MainActor
    private func reallyFinishNavigation(_ navigation: Navigation, webView: WKWebView) {
        guard let currentNavigation,
              currentNavigation == navigation
        else {
            // another navigation have started
            return
        }
        switch currentNavigation.state {
        case .awaitingRedirect, .redirected:
            os_log("%s: ignoring didFinish event because of client-redirect", log: self.logger, type: .default, currentNavigation.debugDescription)
            return
        case .awaitingFinishOrClientRedirect:
            break
        case .expected, .started, .responseReceived, .finished, .failed:
            assertionFailure("unexpected state \(currentNavigation.state)")
        }
        currentNavigation.didFinish()
        os_log("%s did finish: %s", log: self.logger, type: .default, webView.debugDescription, currentNavigation.debugDescription)

        for responder in responders {
            responder.navigationDidFinish(currentNavigation)
        }
        self.currentNavigation = nil
    }

    @MainActor
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        let error = error as? WKError ?? WKError(_nsError: error as NSError)
        guard let currentNavigation else {
            assertionFailure("Unexpected navigationDidFail")
            return
        }
        assert(currentNavigation.matches(navigation))

        currentNavigation.didFail(with: error)
        os_log("%s did fail %s with: %s", log: self.logger, type: .default, webView.debugDescription, currentNavigation.debugDescription, error.localizedDescription)

        for responder in responders {
            responder.navigation(currentNavigation, didFailWith: error, isProvisioned: false)
        }
        self.currentNavigation = nil
    }

    @MainActor
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
        let error = error as? WKError ?? WKError(_nsError: error as NSError)
        guard let currentNavigation else {
            assertionFailure("Unexpected navigationDidFail")
            return
        }
        assert(currentNavigation.matches(navigation))

        currentNavigation.didFail(with: error)
        os_log("%s did fail provisional navigation %s with: %s", log: self.logger, type: .default, webView.debugDescription, currentNavigation.debugDescription, error.localizedDescription)

        for responder in responders {
            responder.navigation(currentNavigation, didFailWith: error, isProvisioned: true)
        }
        self.currentNavigation = nil
    }

    @MainActor
    @available(macOS 11.3, iOS 14.5, *) // objc does‘t care about availability
    @objc(webView:navigationAction:didBecomeDownload:)
    public func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        for responder in responders {
            responder.navigationAction(NavigationAction(navigationAction), didBecome: download)
        }
    }

    @MainActor
    @available(macOS 11.3, iOS 14.5, *) // objc does‘t care about availability
    @objc(webView:navigationResponse:didBecomeDownload:)
    public func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        for responder in responders {
            responder.navigationResponse(NavigationResponse(navigationResponse: navigationResponse, navigation: currentNavigation), didBecome: download)
        }
    }

    @MainActor
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        currentNavigation?.didFail(with: WKError(WKError.Code.webContentProcessTerminated))
        os_log("%s process did terminate; current navigation: %s", log: self.logger, type: .default, webView.debugDescription, currentNavigation?.debugDescription ?? "<nil>")

        for responder in responders {
            responder.webContentProcessDidTerminate(currentNavigation: currentNavigation)
        }
        self.currentNavigation = nil
    }

}

fileprivate protocol AnyResponderRef {
    var responder: NavigationResponder? { get }
    var responderType: String { get }
}

extension DistributedNavigationDelegate.WeakResponderRef where T: AnyObject {
    convenience init(_ responder: T) {
        self.init(responder: responder)
    }
}

extension DistributedWKNavigationDelegate {

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

    public final var responders: [NavigationResponder] {
        return responderRefs.enumerated().reversed().compactMap { (idx, ref) in
            guard let responder = ref.responder else {
                responderRefs.remove(at: idx)
                return nil
            }
            return responder
        }.reversed()
    }

}

extension DistributedNavigationDelegate {

    /// Responders can implement custom WKWebView delegate actions
    /// this may affect the designated method not being called, be careful
    public func registerCustomDelegateMethodHandler(_ handler: ResponderRefMaker, for selector: Selector) {
        assert(self.customDelegateMethodHandlers[selector] == nil)
        self.customDelegateMethodHandlers[selector] = handler.ref
    }
    public func registerCustomDelegateMethodHandler(_ handler: ResponderRefMaker, for selectors: [Selector]) {
        for selector in selectors {
            registerCustomDelegateMethodHandler(handler, for: selector)
        }
    }

    public override func responds(to selector: Selector!) -> Bool {
        guard !super.responds(to: selector) else { return true }
        return customDelegateMethodHandlers[selector] != nil
    }

    public override func forwardingTarget(for selector: Selector!) -> Any? {
        return customDelegateMethodHandlers[selector]?.responder
    }

}
