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

indirect enum NavType: Equatable {
    case linkActivated(isMiddleClick: Bool)
    case formSubmitted
    case backForward(fromURL: URL?, title: String?)
    case reload
    case formResubmitted
    case redirect(type: RedirectType, previousNavigation: EquatableNav?)
    case sessionRestoration
    case userInitatedJavascriptRedirect
    case custom(UserInfo)
    case unknown

    init(_ navigationType: NavigationType) {
        switch navigationType {
        case .linkActivated(let isMiddleClick):
            self = .linkActivated(isMiddleClick: isMiddleClick)
        case .formSubmitted:
            self = .formSubmitted
        case .backForward(let from):
            self = .backForward(fromURL: from?.url, title: from?.title)
        case .reload:
            self = .reload
        case .formResubmitted:
            self = .formResubmitted
        case .redirect(let type, let previousNavigation):
            self = .redirect(type: type, previousNavigation: previousNavigation.map(EquatableNav.init))
        case .sessionRestoration:
            self = .sessionRestoration
        case .userInitatedJavascriptRedirect:
            self = .userInitatedJavascriptRedirect
        case .custom(let userInfo):
            self = .custom(userInfo)
        case .unknown:
            self = .unknown
        }
    }

}
struct NavAction: Equatable, CustomStringConvertible {
    public let navigationType: NavType
    public let url: URL
    public let sourceFrameIsMain: Bool
    public let targetFrameIsMain: Bool

    init(_ navigationAction: NavigationAction) {
        self.navigationType = .init(navigationAction.navigationType)
        self.url = navigationAction.url
        self.sourceFrameIsMain = navigationAction.sourceFrame.isMainFrame
        self.targetFrameIsMain = navigationAction.targetFrame.isMainFrame
    }

    init(navigationType: NavType, url: URL, sourceFrameIsMain: Bool = true, targetFrameIsMain: Bool = true) {
        self.navigationType = navigationType
        self.url = url
        self.sourceFrameIsMain = sourceFrameIsMain
        self.targetFrameIsMain = targetFrameIsMain
    }

    var description: String {
        "\(navigationType):\(url.absoluteString):\(sourceFrameIsMain ? "main" : "iframe")->\(targetFrameIsMain ? "main" : "iframe")"
    }
}
struct NavPrefs: Equatable, CustomStringConvertible {
    var userAgent: String?
    var contentMode: WKWebpagePreferences.ContentMode
    var javaScriptEnabled: Bool
    init(_ prefs: NavigationPreferences) {
        self.userAgent = prefs.userAgent
        self.contentMode = prefs.contentMode
        self.javaScriptEnabled = prefs.javaScriptEnabled
    }
    init(userAgent: String?, contentMode: WKWebpagePreferences.ContentMode, javaScriptEnabled: Bool) {
        self.userAgent = userAgent
        self.contentMode = contentMode
        self.javaScriptEnabled = javaScriptEnabled
    }
    var description: String {
        "\(userAgent ?? "")\(contentMode == .recommended ? "" : (contentMode == .mobile ? ":mobile" : "desktop"))\(javaScriptEnabled == false ? ":jsdisabled" : "")"
    }
}
enum NavState: Equatable {
    case expected
    case started
    case awaitingFinishOrClientRedirect

    case awaitingRedirect(type: RedirectType, url: URL?)
    case redirected

    case responseReceived(URL)
    case finished
    case failed(WKError)

    init(_ state: NavigationState) {
        switch state {
        case .expected:
            self = .expected
        case .started:
            self = .started
        case .awaitingFinishOrClientRedirect:
            self = .awaitingFinishOrClientRedirect
        case .awaitingRedirect(let type, let url):
            self = .awaitingRedirect(type: type, url: url)
        case .redirected:
            self = .redirected
        case .responseReceived(let uRLResponse):
            self = .responseReceived(uRLResponse.url!)
        case .finished:
            self = .finished
        case .failed(let wKError):
            self = .failed(wKError)
        }
    }
}
struct EquatableNav: Equatable, CustomStringConvertible {
    let navigationAction: NavAction
    let state: NavState
    let isCommitted: Bool
    let isSimulated: Bool?
    let userInfo: UserInfo

    init(_ navigation: Navigation) {
        self.navigationAction = .init(navigation.navigationAction)
        self.state = .init(navigation.state)
        self.isCommitted = navigation.isCommitted
        self.userInfo = navigation.userInfo
        self.isSimulated = navigation.isSimulated
    }

    init(navigationAction: NavAction, state: NavState, isCommitted: Bool = false, isSimulated: Bool?, userInfo: UserInfo = .init()) {
        self.navigationAction = navigationAction
        self.state = state
        self.isCommitted = isCommitted
        self.isSimulated = isSimulated
        self.userInfo = userInfo
    }

    init(navigationAction: NavAction, state: NavState, isCommitted: Bool = false, userInfo: UserInfo = .init()) {
        self.navigationAction = navigationAction
        self.state = state
        self.isCommitted = isCommitted
        self.isSimulated = isCommitted ? false : nil
        self.userInfo = userInfo
    }

    var description: String {
        "\(navigationAction):\(state):\(isCommitted ? "committed " : "")\(isSimulated != nil ? (isSimulated! ? "simulated " : "real ") : "")\(userInfo.isEmpty ? "" : userInfo.debugDescription)"
    }
}
struct EquatableResponse: Equatable, CustomStringConvertible {
    var isForMainFrame: Bool
    var url: URL
    init(_ response: NavigationResponse) {
        self.isForMainFrame = response.isForMainFrame
        self.url = response.url
    }

    init(isForMainFrame: Bool, url: URL) {
        self.isForMainFrame = isForMainFrame
        self.url = url
    }

    var description: String {
        (isForMainFrame ? "main:" : "iframe:") + url.absoluteString
    }
}
struct DownloadInfo: Equatable, CustomStringConvertible {
    var url: URL?
    init(_ download: WebKitDownload) {
        self.url = download.originalRequest?.url
    }

    init(url: URL?) {
        self.url = url
    }

    var description: String {
        url?.absoluteString ?? "<nil>"
    }
}
enum NavigationEvent: Equatable, CustomStringConvertible {
    case navigationAction(NavAction, NavPrefs = .init(userAgent: nil, contentMode: .recommended, javaScriptEnabled: true))
    case willCancel(NavAction, NavigationActionCancellationRelatedAction)
    case didCancel(NavAction,  NavigationActionCancellationRelatedAction)
    case navActionBecameDownload(NavigationAction, DownloadInfo)
    case willStart(NavAction)
    case didStart(EquatableNav)
    case didReceiveAuthenticationChallenge(URLAuthenticationChallenge)
    case navigationResponse(EquatableResponse)
    case navResponseBecameDownload(EquatableResponse, DownloadInfo)
    case didCommit(EquatableNav)
    case didReceiveRedirect(EquatableNav, RedirectType)
    case willFinish(EquatableNav)
    case didFinish(EquatableNav)
    case didFail(EquatableNav, WKError)
    case didTerminate(EquatableNav?)

    var description: String {
        switch self {
        case .navigationAction(let arg, let arg2):
            return "navigationAction(\(arg)\(arg2.description.isEmpty ? "" : ", " + arg2.description))"
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
        case .navigationResponse(let arg):
            return "navigationResponse(\(arg))"
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
            return "didTerminate(\(arg?.description ?? "<nil>"))"
        }
    }
}

class NavigationResponderMock: NavigationResponder {

    var history: [NavigationEvent] = []
    var defaultHandler: (() -> Void)?

    var onNavigationAction: ((NavigationAction, inout NavigationPreferences) async -> NavigationActionPolicy?)?
    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? {
        history.append(.navigationAction(.init(navigationAction), .init(preferences)))
        return await onNavigationAction?(navigationAction, &preferences) ?? {
            defaultHandler?()
            return.next
        }()
    }

    var onWillCancel: ((NavigationAction, NavigationActionCancellationRelatedAction) -> Void)?
    func willCancel(_ navigationAction: NavigationAction, with relatedAction: NavigationActionCancellationRelatedAction) {
        history.append(.willCancel(.init(navigationAction), relatedAction))
        onWillCancel?(navigationAction, relatedAction) ?? defaultHandler?()
    }

    var onDidCancel: ((NavigationAction,  NavigationActionCancellationRelatedAction) -> Void)?
    func didCancel(_ navigationAction: NavigationAction, with relatedAction: NavigationActionCancellationRelatedAction) {
        history.append(.didCancel(.init(navigationAction), relatedAction))
        onDidCancel?(navigationAction, relatedAction) ?? defaultHandler?()
    }

    var onNavActionBecameDownload: ((NavigationAction, WebKitDownload) -> Void)?
    func navigationAction(_ navigationAction: NavigationAction, didBecome download: WebKitDownload) {
        history.append(.navActionBecameDownload(navigationAction, .init(download)))
        onNavActionBecameDownload?(navigationAction, download) ?? defaultHandler?()
    }

    var onWillStart: ((NavigationAction) -> Void)?
    func willStart(_ navigationAction: NavigationAction) {
        history.append(.willStart(.init(navigationAction)))
        onWillStart?(navigationAction) ?? defaultHandler?()
    }

    var onDidStart: ((Navigation) -> Void)?
    func didStart(_ navigation: Navigation) {
        history.append(.didStart(.init(navigation)))
        onDidStart?(navigation) ?? defaultHandler?()
    }

    var onDidReceiveAuthenticationChallenge: ((URLAuthenticationChallenge) async -> AuthChallengeDisposition?)?
    @MainActor
    func didReceive(_ authenticationChallenge: URLAuthenticationChallenge) async -> AuthChallengeDisposition? {
        history.append(.didReceiveAuthenticationChallenge(authenticationChallenge))
        return await onDidReceiveAuthenticationChallenge?(authenticationChallenge) ?? {
            defaultHandler?()
            return .next
        }()
    }

    var onNavigationResponse: ((NavigationResponse) async -> NavigationResponsePolicy?)?
    func decidePolicy(for navigationResponse: NavigationResponse) async -> NavigationResponsePolicy? {
        history.append(.navigationResponse(.init(navigationResponse)))
        return await onNavigationResponse?(navigationResponse) ?? {
            defaultHandler?()
            return .next
        }()
    }

    var onNavResponseBecameDownload: ((NavigationResponse, WebKitDownload) -> Void)?
    func navigationResponse(_ navigationResponse: NavigationResponse, didBecome download: WebKitDownload) {
        history.append(.navResponseBecameDownload(.init(navigationResponse), .init(download)))
        onNavResponseBecameDownload?(navigationResponse, download) ?? defaultHandler?()
    }

    var onDidCommit: ((Navigation) -> Void)?
    func didCommit(_ navigation: Navigation) {
        history.append(.didCommit(.init(navigation)))
        onDidCommit?(navigation) ?? defaultHandler?()
    }

    var onDidReceiveRedirect: ((Navigation, RedirectType) -> Void)?
    func navigation(_ navigation: Navigation, didReceive redirect: RedirectType) {
        history.append(.didReceiveRedirect(.init(navigation), redirect))
        onDidReceiveRedirect?(navigation, redirect) ?? defaultHandler?()
    }

    var onWillFinish: ((Navigation) -> Void)?
    func navigationWillFinishOrRedirect(_ navigation: Navigation) {
        history.append(.willFinish(.init(navigation)))
        onWillFinish?(navigation) ?? defaultHandler?()
    }

    var onDidFinish: ((Navigation) -> Void)?
    func navigationDidFinish(_ navigation: Navigation) {
        history.append(.didFinish(.init(navigation)))
        onDidFinish?(navigation) ?? defaultHandler?()
    }

    var onDidFail: ((Navigation, WKError) -> Void)?
    func navigation(_ navigation: Navigation, didFailWith error: WKError) {
        history.append(.didFail(.init(navigation), error))
        onDidFail?(navigation, error) ?? defaultHandler?()
    }

    var onDidTerminate: ((Navigation?) -> Void)?
    func webContentProcessDidTerminate(currentNavigation: Navigation?) {
        history.append(.didTerminate(currentNavigation.map(EquatableNav.init)))
        onDidTerminate?(currentNavigation) ?? defaultHandler?()
    }

}
