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
import BrowserServicesKit
import WebKit
import Common

enum NavigationEvent: Equatable, CustomStringConvertible {
    case navigationAction(NavigationAction, NavigationPreferences = .default)
    case willCancel(NavigationAction, NavigationActionCancellationRelatedAction)
    case didCancel(NavigationAction,  NavigationActionCancellationRelatedAction)
    case navActionBecameDownload(NavigationAction, URL)
    case willStart(NavigationAction)
    case didStart(Navigation)
    case didReceiveAuthenticationChallenge(URLAuthenticationChallenge, Navigation?)
    case navigationResponse(NavigationResponse, Navigation?)
    case navResponseBecameDownload(NavigationResponse, URL)
    case didCommit(Navigation)
    case didReceiveRedirect(Navigation, RedirectType)
    case willFinish(Navigation)
    case didFinish(Navigation)
    case didFail(Navigation, WKError)
    case didTerminate(Navigation?)

    var description: String {
        switch self {
        case .navigationAction(let arg, let arg2):
            return "navigationAction(\(arg)\(arg2.debugDescription.isEmpty ? "" : ", " + arg2.debugDescription))"
        case .willCancel(let arg, let arg2):
            return "willCancel(\(arg), \(arg2))"
        case .didCancel(let arg, let arg2):
            return "didCancel(\(arg), \(arg2))"
        case .navActionBecameDownload(let arg, let arg2):
            return "navActionBecameDownload(\(arg), \(arg2))"
        case .willStart(let arg):
            return "willStart(\(arg))"
        case .didStart(let arg):
            return "didStart(\(arg))"
        case .didReceiveAuthenticationChallenge(let arg):
            return "didReceiveAuthenticationChallenge(\(arg))"
        case .navigationResponse(let arg, let arg2):
            return "navigationResponse(\(arg)) current: \(arg2?.debugDescription ?? "<nil>")"
        case .navResponseBecameDownload(let arg, let arg2):
            return "navResponseBecameDownload(\(arg), \(arg2))"
        case .didCommit(let arg):
            return "didCommit(\(arg))"
        case .didReceiveRedirect(let arg, let arg2):
            return "didReceiveRedirect(\(arg), \(arg2))"
        case .willFinish(let arg):
            return "willFinish(\(arg))"
        case .didFinish(let arg):
            return "didFinish(\(arg))"
        case .didFail(let arg, let arg2):
            return "didFail(\(arg), \(arg2))"
        case .didTerminate(let arg):
            return "didTerminate(\(arg?.debugDescription ?? "<nil>"))"
        }
    }
}

class NavigationResponderMock: NavigationResponder {

    var history: [NavigationEvent] = []
    var defaultHandler: (() -> Void)?

    var onNavigationAction: ((NavigationAction, inout NavigationPreferences) async -> NavigationActionPolicy?)?
    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? {
        history.append(.navigationAction(navigationAction, preferences))
        return await onNavigationAction?(navigationAction, &preferences) ?? {
            defaultHandler?()
            return.next
        }()
    }

    var onWillCancel: ((NavigationAction, NavigationActionCancellationRelatedAction) -> Void)?
    func willCancel(_ navigationAction: NavigationAction, with relatedAction: NavigationActionCancellationRelatedAction) {
        history.append(.willCancel(navigationAction, relatedAction))
        onWillCancel?(navigationAction, relatedAction) ?? defaultHandler?()
    }

    var onDidCancel: ((NavigationAction,  NavigationActionCancellationRelatedAction) -> Void)?
    func didCancel(_ navigationAction: NavigationAction, with relatedAction: NavigationActionCancellationRelatedAction) {
        history.append(.didCancel(navigationAction, relatedAction))
        onDidCancel?(navigationAction, relatedAction) ?? defaultHandler?()
    }

    var onNavActionBecameDownload: ((NavigationAction, WebKitDownload) -> Void)?
    func navigationAction(_ navigationAction: NavigationAction, didBecome download: WebKitDownload) {
        history.append(.navActionBecameDownload(navigationAction, download.originalRequest!.url!))
        onNavActionBecameDownload?(navigationAction, download) ?? defaultHandler?()
    }

    var onWillStart: ((NavigationAction) -> Void)?
    func willStart(_ navigationAction: NavigationAction) {
        history.append(.willStart(navigationAction))
        onWillStart?(navigationAction) ?? defaultHandler?()
    }

    var onDidStart: ((Navigation) -> Void)?
    func didStart(_ navigation: Navigation) {
        history.append(.didStart(navigation))
        onDidStart?(navigation) ?? defaultHandler?()
    }

    var onDidReceiveAuthenticationChallenge: ((URLAuthenticationChallenge, Navigation?) async -> AuthChallengeDisposition?)?
    @MainActor
    func didReceive(_ authenticationChallenge: URLAuthenticationChallenge, for navigation: Navigation?) async -> AuthChallengeDisposition? {
        history.append(.didReceiveAuthenticationChallenge(authenticationChallenge))
        return await onDidReceiveAuthenticationChallenge?(authenticationChallenge, navigation) ?? {
            defaultHandler?()
            return .next
        }()
    }

    var onNavigationResponse: ((NavigationResponse, Navigation?) async -> NavigationResponsePolicy?)?
    func decidePolicy(for navigationResponse: NavigationResponse, currentNavigation: Navigation?) async -> NavigationResponsePolicy? {
        history.append(.navigationResponse(navigationResponse, currentNavigation))
        return await onNavigationResponse?(navigationResponse, currentNavigation) ?? {
            defaultHandler?()
            return .next
        }()
    }

    var onNavResponseBecameDownload: ((NavigationResponse, WebKitDownload) -> Void)?
    func navigationResponse(_ navigationResponse: NavigationResponse, didBecome download: WebKitDownload, currentNavigation: Navigation?) {
        history.append(.navResponseBecameDownload(navigationResponse, download.originalRequest!.url!))
        onNavResponseBecameDownload?(navigationResponse, download) ?? defaultHandler?()
    }

    var onDidCommit: ((Navigation) -> Void)?
    func didCommit(_ navigation: Navigation) {
        history.append(.didCommit(navigation))
        onDidCommit?(navigation) ?? defaultHandler?()
    }

    var onDidReceiveRedirect: ((Navigation, RedirectType) -> Void)?
    func navigation(_ navigation: Navigation, didReceive redirect: RedirectType) {
        history.append(.didReceiveRedirect(navigation, redirect))
        onDidReceiveRedirect?(navigation, redirect) ?? defaultHandler?()
    }

    var onWillFinish: ((Navigation) -> Void)?
    func navigationWillFinishOrRedirect(_ navigation: Navigation) {
        history.append(.willFinish(navigation))
        onWillFinish?(navigation) ?? defaultHandler?()
    }

    var onDidFinish: ((Navigation) -> Void)?
    func navigationDidFinish(_ navigation: Navigation) {
        history.append(.didFinish(navigation))
        onDidFinish?(navigation) ?? defaultHandler?()
    }

    var onDidFail: ((Navigation, WKError) -> Void)?
    func navigation(_ navigation: Navigation, didFailWith error: WKError) {
        history.append(.didFail(navigation, error))
        onDidFail?(navigation, error) ?? defaultHandler?()
    }

    var onDidTerminate: ((Navigation?) -> Void)?
    func webContentProcessDidTerminate(currentNavigation: Navigation?) {
        history.append(.didTerminate(currentNavigation))
        onDidTerminate?(currentNavigation) ?? defaultHandler?()
    }

}
