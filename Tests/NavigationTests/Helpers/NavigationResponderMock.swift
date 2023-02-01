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

enum TestsNavigationEvent: Equatable {
    case navigationAction(NavAction, NavigationPreferences = .default)
    case navActionWillBecomeDownload(NavAction)
    case navActionBecameDownload(NavAction, String)
    case willStart(Nav)
    case didStart(Nav)
    case didReceiveAuthenticationChallenge(URLProtectionSpace, Nav?)

    enum EitherResponseOrNavigation: Equatable {
        case response(NavResponse, navigation: Nav?)
        case navigation(Nav)
        var response: NavigationResponse {
            switch self {
            case .response(let resp, navigation: _): return resp.response
            case .navigation(let nav): return nav.response!.response
            }
        }
        static func == (lhs: TestsNavigationEvent.EitherResponseOrNavigation, rhs: TestsNavigationEvent.EitherResponseOrNavigation) -> Bool {
            switch lhs {
            case .response(let resp1, navigation: let nav1):
                if case .response(let resp2, navigation: let nav2) = rhs {
                    return NavigationResponse.difference(between: resp1.response, and: resp2.response) == nil && nav1 == nav2
                }
            case .navigation(let nav):
                if case .navigation(nav) = rhs {
                    return true
                }
            }
            return false
        }
    }
    case navigationResponse(EitherResponseOrNavigation)
    case navResponseWillBecomeDownload(Int)
    case navResponseBecameDownload(Int, URL)
    case didCommit(Nav)
    case didReceiveRedirect(NavAction, Nav)
    case didFinish(Nav)
    case didFail(Nav, /*code:*/ Int, isProvisional: Bool)
    case didTerminate(Nav?)

    static func navigationAction(_ navigationAction: NavigationAction, _ prefs: NavigationPreferences = .default) -> TestsNavigationEvent {
        return .navigationAction(NavAction(navigationAction), prefs)
    }
    static func navActionWillBecomeDownload(_ navigationAction: NavigationAction) -> TestsNavigationEvent {
        return .navActionWillBecomeDownload(NavAction(navigationAction))
    }
    static func navActionBecameDownload(_ navigationAction: NavAction, _ url: URL) -> TestsNavigationEvent {
        return .navActionBecameDownload(navigationAction, url.string.dropping(suffix: "/"))
    }
    static func didFail(_ nav: Nav, _ code: Int) -> TestsNavigationEvent {
        return .didFail(nav, code, isProvisional: true)
    }

    static func didReceiveRedirect(_ nav: Nav) -> TestsNavigationEvent {
        return .didReceiveRedirect(nav.navigationAction, nav)
    }

    var redirectEvent: Nav? {
        if case .didReceiveRedirect(_, let nav) = self { return nav }
        return nil
    }
}

struct NavAction: Equatable, TestComparable {
    let navigationAction: NavigationAction

    init(_ request: URLRequest, _ navigationType: NavigationType, from currentHistoryItemIdentity: HistoryItemIdentity? = nil, redirects: [NavAction]? = nil, _ isUserInitiated: NavigationAction.UserInitiated? = nil, src: FrameInfo, targ: FrameInfo? = nil, _ shouldDownload: NavigationAction.ShouldDownload? = nil) {
        self.navigationAction = .init(request: request, navigationType: navigationType, currentHistoryItemIdentity: currentHistoryItemIdentity, redirectHistory: redirects?.map(\.navigationAction), isUserInitiated: isUserInitiated != nil, sourceFrame: src, targetFrame: targ ?? src, shouldDownload: shouldDownload != nil, mainFrameNavigation: nil) // TODO: check mainFrameNavigation
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

extension Nav: TestComparable {
    static func difference(between lhs: Nav, and rhs: Nav) -> String? {
        compare_tc("navigationAction", lhs.navigationAction, rhs.navigationAction)
        ?? compare("response", lhs.response?.response, rhs.response?.response)
        ?? compare("redirects", lhs.redirects, rhs.redirects)
        ?? compare("state", lhs.state, rhs.state)
        ?? compare("isCommitted", lhs.isCommitted, rhs.isCommitted)
        ?? compare("didReceiveAuthenticationChallenge", lhs.didReceiveAuthenticationChallenge, rhs.didReceiveAuthenticationChallenge)
    }
}

class NavigationResponderMock: NavigationResponder {

    private(set) var history: [TestsNavigationEvent] = []
    private(set) var navigations: [Navigation] = []
    var navigationActionsCache: (dict: [UInt64: NavAction], max: UInt64) = ([:], 0)
    private(set) var navigationResponses: [NavResponse] = []

    static let defaultHandler: ((TestsNavigationEvent) -> Void) = {
        fatalError("not handled: \($0)")
    }
    var defaultHandler: ((TestsNavigationEvent) -> Void)

    init(defaultHandler: @escaping ((TestsNavigationEvent) -> Void) = NavigationResponderMock.defaultHandler) {
        self.defaultHandler = defaultHandler
    }

    func reset() {
        clear()
        
        onNavigationAction = nil
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

    private func append(_ event: TestsNavigationEvent) -> TestsNavigationEvent {
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

    var onWillStart: (@MainActor (Navigation) -> Void)?
    func willStart(_ navigation: Navigation) {
        if navigationActionsCache.dict[navigation.navigationAction.identifier] == nil {
            navigationActionsCache.dict[navigation.navigationAction.identifier] = .init(navigation.navigationAction)
            navigationActionsCache.max = max(navigationActionsCache.max, navigation.navigationAction.identifier)
        }

        navigations.append(navigation)
        let event = append(.willStart(Nav(navigation)))
        onWillStart?(navigation) ?? defaultHandler(event)
    }

    @MainActor
    func Nav(_ navigation: Navigation) -> Nav {
        NavigationTests.Nav(action: .init(navigation.navigationAction),
                            redirects: navigation.redirectHistory.map { NavAction($0) },
                            navigation.state,
                            resp: navigation.navigationResponse.map(NavResponse.init),
                            navigation.isCommitted ? .committed : nil,
                            navigation.didReceiveAuthenticationChallenge ? .gotAuth : nil)
    }
    @MainActor
    func Nav(_ navigation: Navigation?) -> Nav? {
        navigation == nil ? nil : .some(Nav(navigation!))
    }

    var onDidStart: (@MainActor (Navigation) -> Void)?
    func didStart(_ navigation: Navigation) {
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
    func didReceiveRedirect(_ navigationAction: NavigationAction, for navigation: Navigation) {
        let event = append(.didReceiveRedirect(NavAction(navigationAction), Nav(navigation)))
        onDidReceiveRedirect?(navigationAction, navigation) ?? {
            defaultHandler(event)
        }()
    }

    var onNavigationResponse: (@MainActor (NavigationResponse) async -> NavigationResponsePolicy?)?
    @MainActor
    func decidePolicy(for navigationResponse: NavigationResponse) async -> NavigationResponsePolicy? {
        navigationResponses.append(NavResponse(response: navigationResponse))
        let event = append(.navigationResponse(navigationResponse.isForMainFrame ? .navigation(Nav(navigationResponse.mainFrameNavigation!))
                                               : .response(NavResponse(response: navigationResponse), navigation: Nav(navigationResponse.mainFrameNavigation))))
        return await onNavigationResponse?(navigationResponse) ?? {
            defaultHandler(event)
            return .next
        }()

    }

    var onNavResponseWillBecomeDownload: (@MainActor (NavigationResponse) -> Void)?
    func navigationResponse(_ navigationResponse: NavigationResponse, willBecomeDownloadIn webView: WKWebView) {
        let event = append(.navResponseWillBecomeDownload(navigationResponses.firstIndex(of: NavResponse(response: navigationResponse))!))
        onNavResponseWillBecomeDownload?(navigationResponse) ?? defaultHandler(event)
    }

    var onNavResponseBecameDownload: (@MainActor (NavigationResponse, WebKitDownload) -> Void)?
    @MainActor
    func navigationResponse(_ navigationResponse: NavigationResponse, didBecome download: WebKitDownload) {
        let event = append(.navResponseBecameDownload(navigationResponses.firstIndex(of: NavResponse(response: navigationResponse))!, download.originalRequest!.url!))
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

    var onDidFail: (@MainActor (Navigation, WKError, Bool) -> Void)?
    func navigation(_ navigation: Navigation, didFailWith error: WKError, isProvisional: Bool) {
        let event = append(.didFail(Nav(navigation), error.code.rawValue, isProvisional: false))
        onDidFail?(navigation, error, isProvisional) ?? defaultHandler(event)
    }

    var onDidTerminate: (@MainActor (Navigation?) -> Void)?
    func webContentProcessDidTerminate(currentNavigation navigation: Navigation?) {
        let event = append(.didTerminate(Nav(navigation)))
        onDidTerminate?(navigation) ?? defaultHandler(event)
    }

}
