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

enum NavigationEvent: Equatable {
    case navigationAction(NavAction, NavigationPreferences = .default)
    case willCancel(NavAction, NavigationActionCancellationRelatedAction)
    case didCancel(NavAction,  NavigationActionCancellationRelatedAction = .none)
    case navActionBecameDownload(NavAction, URL)
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
    case navResponseBecameDownload(Int, URL)
    case didCommit(Nav)
    case didReceiveRedirect(Nav)
    case didFinish(Nav)
    case didFail(Nav, /*code:*/ Int)
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
    static func navActionBecameDownload(_ navigationAction: NavigationAction, _ url: URL) -> NavigationEvent {
        return .navActionBecameDownload(NavAction(navigationAction), url)
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
    var navigationActionsCache: [NavAction] = []
    private(set) var navigationResponses: [NavigationResponse] = []

    var defaultHandler: ((NavigationEvent) -> Void) = {
        fatalError("not handled: \($0)")
    }

    init(defaultHandler: ((NavigationEvent) -> Void)? = nil) {
        if let defaultHandler {
            self.defaultHandler = defaultHandler
        }
    }

    func clear() {
        history = []
        navigations = []
        navigationActionsCache = []
        navigationResponses = []
    }

    private func append(_ event: NavigationEvent) -> NavigationEvent {
        history.append(event)
        return event
    }

    var onNavigationAction: (@MainActor (NavigationAction, inout NavigationPreferences) async -> NavigationActionPolicy?)?
    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? {
        let event = append(.navigationAction(navigationAction, preferences))
        guard let onNavigationAction = onNavigationAction else {
            defaultHandler(event)
            return.next
        }
        return await onNavigationAction(navigationAction, &preferences)
    }

    var onWillCancel: ((NavigationAction, NavigationActionCancellationRelatedAction) -> Void)?
    func willCancel(_ navigationAction: NavigationAction, with relatedAction: NavigationActionCancellationRelatedAction) {
        let event = append(.willCancel(navigationAction, relatedAction))
        onWillCancel?(navigationAction, relatedAction) ?? defaultHandler(event)
    }

    var onDidCancel: ((NavigationAction,  NavigationActionCancellationRelatedAction) -> Void)?
    func didCancel(_ navigationAction: NavigationAction, with relatedAction: NavigationActionCancellationRelatedAction) {
        let event = append(.didCancel(navigationAction, relatedAction))
        onDidCancel?(navigationAction, relatedAction) ?? defaultHandler(event)
    }

    var onNavActionBecameDownload: ((NavigationAction, WebKitDownload) -> Void)?
    func navigationAction(_ navigationAction: NavigationAction, didBecome download: WebKitDownload) {
        let event = append(.navActionBecameDownload(navigationAction, download.originalRequest!.url!))
        onNavActionBecameDownload?(navigationAction, download) ?? defaultHandler(event)
    }

    var onWillStart: ((NavigationAction) -> Void)?
    func willStart(_ navigationAction: NavigationAction) {
        let event = append(.willStart(.init(navigationAction)))
        onWillStart?(navigationAction) ?? defaultHandler(event)
    }

    func Nav(_ navigation: Navigation) -> Nav {
        NavigationTests.Nav(action: .init(navigation.navigationAction),
                            redirects: navigation.redirectHistory.map { NavAction($0) },
                            navigation.state,
                            navigation.isCommitted ? .committed : nil,
                            navigation.didReceiveAuthenticationChallenge ? .gotAuth : nil)
    }
    func Nav(_ navigation: Navigation?) -> Nav? {
        navigation == nil ? nil : .some(Nav(navigation!))
    }

    var onDidStart: ((Navigation) -> Void)?
    func didStart(_ navigation: Navigation) {
        navigations.append(navigation)
        let event = append(.didStart(Nav(navigation)))
        onDidStart?(navigation) ?? defaultHandler(event)
    }

    var onDidReceiveAuthenticationChallenge: ((URLAuthenticationChallenge, Navigation?) async -> AuthChallengeDisposition?)?
    @MainActor
    func didReceive(_ authenticationChallenge: URLAuthenticationChallenge, for navigation: Navigation?) async -> AuthChallengeDisposition? {
        let event = append(.didReceiveAuthenticationChallenge(authenticationChallenge.protectionSpace, Nav(navigation)))
        return await onDidReceiveAuthenticationChallenge?(authenticationChallenge, navigation) ?? {
            defaultHandler(event)
            return .next
        }()
    }

    var onDidReceiveRedirect: ((NavigationAction, Navigation) -> Void)?
    @MainActor
    func didReceiveServerRedirect(_ navigationAction: NavigationAction, for navigation: Navigation) {
        assert(NavAction(navigation.navigationAction) == NavAction(navigationAction))
        let event = append(.didReceiveRedirect(Nav(navigation)))
        onDidReceiveRedirect?(navigationAction, navigation) ?? {
            defaultHandler(event)
        }()
    }

    var onNavigationResponse: ((NavigationResponse, Navigation?) async -> NavigationResponsePolicy?)?
    func decidePolicy(for navigationResponse: NavigationResponse, currentNavigation navigation: Navigation?) async -> NavigationResponsePolicy? {
        navigationResponses.append(navigationResponse)
        assert(navigation == nil || !navigationResponse.isForMainFrame || navigation!.state == .responseReceived(navigationResponse))
        let event = append(.navigationResponse(navigation == nil || !navigationResponse.isForMainFrame
                                               ? .response(navigationResponse, navigation: navigation.map(Nav(_:)))
                                               : .navigation(Nav(navigation!))))
        return await onNavigationResponse?(navigationResponse, navigation) ?? {
            defaultHandler(event)
            return .next
        }()
    }

    var onNavResponseBecameDownload: ((NavigationResponse, WebKitDownload) -> Void)?
    func navigationResponse(_ navigationResponse: NavigationResponse, didBecome download: WebKitDownload, currentNavigation navigation: Navigation?) {
        let event = append(.navResponseBecameDownload(navigationResponses.firstIndex(of: navigationResponse)!, download.originalRequest!.url!))
        onNavResponseBecameDownload?(navigationResponse, download) ?? defaultHandler(event)
    }

    var onDidCommit: ((Navigation) -> Void)?
    func didCommit(_ navigation: Navigation) {
        let event = append(.didCommit(Nav(navigation)))
        onDidCommit?(navigation) ?? defaultHandler(event)
    }

    var onDidFinish: ((Navigation) -> Void)?
    func navigationDidFinish(_ navigation: Navigation) {
        let event = append(.didFinish(Nav(navigation)))
        onDidFinish?(navigation) ?? defaultHandler(event)
    }

    var onDidFail: ((Navigation, WKError) -> Void)?
    func navigation(_ navigation: Navigation, didFailWith error: WKError, isProvisioned: Bool) {
        let event = append(.didFail(Nav(navigation), error.code.rawValue))
        onDidFail?(navigation, error) ?? defaultHandler(event)
    }

    var onDidTerminate: ((Navigation?) -> Void)?
    func webContentProcessDidTerminate(currentNavigation navigation: Navigation?) {
        let event = append(.didTerminate(Nav(navigation)))
        onDidTerminate?(navigation) ?? defaultHandler(event)
    }

}
