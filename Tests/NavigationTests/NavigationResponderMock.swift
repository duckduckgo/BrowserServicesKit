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
    case navigationAction(NavigationAction, NavigationPreferences = .default)
    case willCancel(NavigationAction, NavigationActionCancellationRelatedAction)
    case didCancel(NavigationAction,  NavigationActionCancellationRelatedAction = .none)
    case navActionBecameDownload(NavigationAction, URL)
    case willStart(Int)
    case didStart(Nav)
    case didReceiveAuthenticationChallenge(URLProtectionSpace, Nav?)

    enum EitherResponseOrNavigation: Equatable {
        case response(NavigationResponse)
        case navigation(Nav)
        var response: NavigationResponse {
            switch self {
            case .response(let resp): return resp
            case .navigation(let nav): return nav.state.response!
            }
        }
    }
    case navigationResponse(EitherResponseOrNavigation)
    case navResponseBecameDownload(Int, URL)
    case didCommit(Nav)
    case didReceiveRedirect(Nav, RedirectType)
    case didFinish(Nav)
    case didFail(Nav, /*code:*/ Int)
    case didTerminate(Nav?)
}

class NavigationResponderMock: NavigationResponder {

    private(set) var history: [NavigationEvent] = []
    private(set) var navigations: [Navigation] = []
    private(set) var navigationActions: [NavigationAction] = []
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
        navigationActions = []
        navigationResponses = []
    }

    private func append(_ event: NavigationEvent) -> NavigationEvent {
        history.append(event)
        return event
    }

    var onNavigationAction: ((NavigationAction, inout NavigationPreferences) async -> NavigationActionPolicy?)?
    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? {
        let event = append(.navigationAction(navigationAction, preferences))
        navigationActions.append(navigationAction)
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
        let actionIdx: Int
        if let idx = navigationActions.firstIndex(of: navigationAction) {
            actionIdx = idx
        } else {
            navigationActions.append(navigationAction)
            actionIdx = navigationActions.count - 1
        }

        let event = append(.willStart(actionIdx))
        onWillStart?(navigationAction) ?? defaultHandler(event)
    }

    func Nav(_ navigation: Navigation) -> Nav {
        let actionIdx: Int
        if let idx = navigationActions.firstIndex(of: navigation.navigationAction) {
            actionIdx = idx
        } else {
            navigationActions.append(navigation.navigationAction)
            actionIdx = navigationActions.count - 1
        }
        return NavigationTests.Nav(act: actionIdx, navigation)
    }
    func Nav(_ navigation: Navigation?) -> Nav? {
        navigation == nil ? nil :
            NavigationTests.Nav(act: navigationActions.firstIndex(of: navigation!.navigationAction)!, navigation!)
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

    var onNavigationResponse: ((NavigationResponse, Navigation?) async -> NavigationResponsePolicy?)?
    func decidePolicy(for navigationResponse: NavigationResponse, currentNavigation navigation: Navigation?) async -> NavigationResponsePolicy? {
        navigationResponses.append(navigationResponse)
        assert(navigation == nil || navigation!.state == .responseReceived(navigationResponse))
        let event = append(.navigationResponse(navigation == nil ? .response(navigationResponse) : .navigation(Nav(navigation!))))
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
