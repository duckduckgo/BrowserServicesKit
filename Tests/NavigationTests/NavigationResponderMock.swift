//
//  NavigationResponderMock.swift
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
import Navigation
import WebKit
import Common

// swiftlint:disable line_length
// swiftlint:disable identifier_name

enum NavigationEvent: Equatable {
    case navigationAction(NavAction, NavigationPreferences = .default)
    case willCancel(NavAction, NavigationActionCancellationRelatedAction)
    case didCancel(NavAction, NavigationActionCancellationRelatedAction = .none)
    case navActionWillBecomeDownload(NavAction)
    case navActionBecameDownload(NavAction, String)
    case willStart(NavAction)
    case didStart(Nav)
    case didReceiveAuthenticationChallenge(URLProtectionSpace, Nav?)

    enum EitherResponseOrNavigation: Equatable {
        case response(NavigationResponse, navigation: Nav?)
        case navigation(Nav)
        var response: NavigationResponse {
            switch self {
            case .response(let resp, navigation: _): return resp
            case .navigation(let nav): return nav.state.response!
            }
        }
    }
    case navigationResponse(EitherResponseOrNavigation)
    case navResponseWillBecomeDownload(Int)
    case navResponseBecameDownload(Int, URL)
    case didCommit(Nav)
    case didReceiveRedirect(Nav)
    case didFinish(Nav)
    case didFail(Nav, /*code:*/ Int, isProvisioned: Bool)
    case didTerminate(Nav?)

    static func navigationAction(_ navigationAction: NavigationAction, _ prefs: NavigationPreferences = .default) -> NavigationEvent {
        return .navigationAction(NavAction(navigationAction), prefs)
    }
    static func willCancel(_ navigationAction: NavigationAction, _ action: NavigationActionCancellationRelatedAction) -> NavigationEvent {
        return .willCancel(NavAction(navigationAction), action)
    }
    static func didCancel(_ navigationAction: NavigationAction, _ action: NavigationActionCancellationRelatedAction = .none) -> NavigationEvent {
        return .didCancel(NavAction(navigationAction), action)
    }
    static func navActionWillBecomeDownload(_ navigationAction: NavigationAction) -> NavigationEvent {
        return .navActionWillBecomeDownload(NavAction(navigationAction))
    }
    static func navActionBecameDownload(_ navigationAction: NavAction, _ url: URL) -> NavigationEvent {
        return .navActionBecameDownload(navigationAction, url.string.dropping(suffix: "/"))
    }
    static func didFail(_ nav: Nav, _ code: Int) -> NavigationEvent {
        return .didFail(nav, code, isProvisioned: true)
    }

    var redirectEvent: Nav? {
        if case .didReceiveRedirect(let nav) = self { return nav }
        return nil
    }
}

struct NavAction: Equatable, TestComparable {
    let navigationAction: NavigationAction

    init(_ request: URLRequest, _ navigationType: NavigationType, from currentHistoryItemIdentity: HistoryItemIdentity? = nil, redirects: [NavAction]? = nil, _ isUserInitiated: NavigationAction.UserInitiated? = nil, src: FrameInfo, targ: FrameInfo? = nil, _ shouldDownload: NavigationAction.ShouldDownload? = nil) {
        self.navigationAction = .init(request: request, navigationType: navigationType, currentHistoryItemIdentity: currentHistoryItemIdentity, redirectHistory: redirects?.map(\.navigationAction), isUserInitiated: isUserInitiated != nil, sourceFrame: src, targetFrame: targ ?? src, shouldDownload: shouldDownload != nil)
    }

    init(_ navigationAction: NavigationAction) {
        self.navigationAction = navigationAction
    }

    static func difference(between lhs: NavAction, and rhs: NavAction) -> String? {
        NavigationAction.difference(between: lhs.navigationAction, and: rhs.navigationAction)
    }

    static func == (lhs: NavAction, rhs: NavAction) -> Bool {
        return NavigationAction.difference(between: lhs.navigationAction, and: rhs.navigationAction) == nil
    }
}

class NavigationResponderMock: NavigationResponder {

    private(set) var history: [NavigationEvent] = []
    private(set) var navigations: [Navigation] = []
    var navigationActionsCache: (dict: [UInt64: NavAction], max: UInt64) = ([:], 0)
    private(set) var navigationResponses: [NavigationResponse] = []

    static let defaultHandler: ((NavigationEvent) -> Void) = {
        fatalError("not handled: \($0)")
    }
    var defaultHandler: ((NavigationEvent) -> Void)

    init(defaultHandler: @escaping ((NavigationEvent) -> Void) = NavigationResponderMock.defaultHandler) {
        self.defaultHandler = defaultHandler
    }

    func reset() {
        clear()
        
        onNavigationAction = nil
        onWillCancel = nil
        onDidCancel = nil
        onWillStart = nil
        onDidStart = nil
        onDidReceiveAuthenticationChallenge = nil
        onDidReceiveRedirect = nil
        onNavigationResponse = nil
        onDidFail = nil
        onDidFinish = nil
        onDidCommit = nil
        onDidTerminate = nil

        onNavActionWillBecomeDownload = nil
        onNavActionBecameDownload = nil

        onNavResponseWillBecomeDownload = nil
        onNavResponseBecameDownload = nil

        defaultHandler = { 
            fatalError("event received after test completed: \($0)")
        }
    }
    func clear() {
        history = []
    }

    private func append(_ event: NavigationEvent) -> NavigationEvent {
        history.append(event)
        return event
    }

    var onNavigationAction: (@MainActor (NavigationAction, inout NavigationPreferences) async -> NavigationActionPolicy?)?
    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? {
        navigationActionsCache.dict[navigationAction.identifier] = .init(navigationAction)
        navigationActionsCache.max = max(navigationActionsCache.max, navigationAction.identifier)

        let event = append(.navigationAction(navigationAction, preferences))
        guard let onNavigationAction = onNavigationAction else {
            defaultHandler(event)
            return.next
        }
        return await onNavigationAction(navigationAction, &preferences)
    }

    var onWillCancel: (@MainActor (NavigationAction, NavigationActionCancellationRelatedAction) -> Void)?
    func willCancel(_ navigationAction: NavigationAction, with relatedAction: NavigationActionCancellationRelatedAction) {
        let event = append(.willCancel(navigationAction, relatedAction))
        onWillCancel?(navigationAction, relatedAction) ?? defaultHandler(event)
    }

    var onDidCancel: (@MainActor (NavigationAction, NavigationActionCancellationRelatedAction) -> Void)?
    func didCancel(_ navigationAction: NavigationAction, with relatedAction: NavigationActionCancellationRelatedAction) {
        let event = append(.didCancel(navigationAction, relatedAction))
        onDidCancel?(navigationAction, relatedAction) ?? defaultHandler(event)
    }

    var onNavActionWillBecomeDownload: (@MainActor (NavigationAction) -> Void)?
    func navigationAction(_ navigationAction: NavigationAction, willBecomeDownloadIn webView: WKWebView) {
        let event = append(.navActionWillBecomeDownload(navigationAction))
        onNavActionWillBecomeDownload?(navigationAction) ?? defaultHandler(event)
    }

    var onNavActionBecameDownload: (@MainActor (NavigationAction, WebKitDownload) -> Void)?
    func navigationAction(_ navigationAction: NavigationAction, didBecome download: WebKitDownload) {
        let event = append(.navActionBecameDownload(NavAction(navigationAction), download.originalRequest!.url!))
        onNavActionBecameDownload?(navigationAction, download) ?? defaultHandler(event)
    }

    var onWillStart: (@MainActor (NavigationAction) -> Void)?
    func willStart(_ navigationAction: NavigationAction) {
        if navigationActionsCache.dict[navigationAction.identifier] == nil {
            navigationActionsCache.dict[navigationAction.identifier] = .init(navigationAction)
            navigationActionsCache.max = max(navigationActionsCache.max, navigationAction.identifier)
        }

        let event = append(.willStart(.init(navigationAction)))
        onWillStart?(navigationAction) ?? defaultHandler(event)
    }

    @MainActor
    func Nav(_ navigation: Navigation) -> Nav {
        NavigationTests.Nav(action: .init(navigation.navigationAction),
                            redirects: navigation.redirectHistory.map { NavAction($0) },
                            navigation.state,
                            navigation.isCommitted ? .committed : nil,
                            navigation.didReceiveAuthenticationChallenge ? .gotAuth : nil)
    }
    @MainActor
    func Nav(_ navigation: Navigation?) -> Nav? {
        navigation == nil ? nil : .some(Nav(navigation!))
    }

    var onDidStart: (@MainActor (Navigation) -> Void)?
    func didStart(_ navigation: Navigation) {
        navigations.append(navigation)
        let event = append(.didStart(Nav(navigation)))
        onDidStart?(navigation) ?? defaultHandler(event)
    }

    var onDidReceiveAuthenticationChallenge: (@MainActor (URLAuthenticationChallenge, Navigation?) async -> AuthChallengeDisposition?)?
    @MainActor
    func didReceive(_ authenticationChallenge: URLAuthenticationChallenge, for navigation: Navigation?) async -> AuthChallengeDisposition? {
        let event = append(.didReceiveAuthenticationChallenge(authenticationChallenge.protectionSpace, Nav(navigation)))
        return await onDidReceiveAuthenticationChallenge?(authenticationChallenge, navigation) ?? {
            defaultHandler(event)
            return .next
        }()
    }

    var onDidReceiveRedirect: (@MainActor (NavigationAction, Navigation) -> Void)?
    @MainActor
    func didReceiveServerRedirect(_ navigationAction: NavigationAction, for navigation: Navigation) {
        assert(NavAction(navigation.navigationAction) == NavAction(navigationAction))
        let event = append(.didReceiveRedirect(Nav(navigation)))
        onDidReceiveRedirect?(navigationAction, navigation) ?? {
            defaultHandler(event)
        }()
    }

    var onNavigationResponse: (@MainActor (NavigationResponse, Navigation?) async -> NavigationResponsePolicy?)?
    @MainActor
    func decidePolicy(for navigationResponse: NavigationResponse, currentNavigation navigation: Navigation?) async -> NavigationResponsePolicy? {
        navigationResponses.append(navigationResponse)
        assert(navigation == nil || !navigationResponse.isForMainFrame || navigation!.state == .responseReceived(navigationResponse))
        let event = append(.navigationResponse(navigation == nil || !navigationResponse.isForMainFrame
                                               ? .response(navigationResponse, navigation: Nav(navigation))
                                               : .navigation(Nav(navigation!))))
        return await onNavigationResponse?(navigationResponse, navigation) ?? {
            defaultHandler(event)
            return .next
        }()

    }

    var onNavResponseWillBecomeDownload: (@MainActor (NavigationResponse) -> Void)?
    func navigationResponse(_ navigationResponse: NavigationResponse, willBecomeDownloadIn webView: WKWebView) {
        let event = append(.navResponseWillBecomeDownload(navigationResponses.firstIndex(of: navigationResponse)!))
        onNavResponseWillBecomeDownload?(navigationResponse) ?? defaultHandler(event)
    }

    var onNavResponseBecameDownload: (@MainActor (NavigationResponse, WebKitDownload) -> Void)?
    func navigationResponse(_ navigationResponse: NavigationResponse, didBecome download: WebKitDownload, currentNavigation navigation: Navigation?) {
        let event = append(.navResponseBecameDownload(navigationResponses.firstIndex(of: navigationResponse)!, download.originalRequest!.url!))
        onNavResponseBecameDownload?(navigationResponse, download) ?? defaultHandler(event)
    }

    var onDidCommit: (@MainActor (Navigation) -> Void)?
    func didCommit(_ navigation: Navigation) {
        let event = append(.didCommit(Nav(navigation)))
        onDidCommit?(navigation) ?? defaultHandler(event)
    }

    var onDidFinish: (@MainActor (Navigation) -> Void)?
    func navigationDidFinish(_ navigation: Navigation) {
        let event = append(.didFinish(Nav(navigation)))
        onDidFinish?(navigation) ?? defaultHandler(event)
    }

    var onDidFail: (@MainActor (Navigation, WKError) -> Void)?
    func navigation(_ navigation: Navigation, didFailWith error: WKError, isProvisioned: Bool) {
        let event = append(.didFail(Nav(navigation), error.code.rawValue, isProvisioned: false))
        onDidFail?(navigation, error) ?? defaultHandler(event)
    }

    var onDidTerminate: (@MainActor (Navigation?) -> Void)?
    func webContentProcessDidTerminate(currentNavigation navigation: Navigation?) {
        let event = append(.didTerminate(Nav(navigation)))
        onDidTerminate?(navigation) ?? defaultHandler(event)
    }

}
