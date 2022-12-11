//
//  NavigationResponder.swift
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

public protocol NavigationResponder {

    // MARK: Decision making

    /// Decides whether to allow or cancel a navigation
    /// Navigation Responders are queried in the provided order until any of them returns a NavigationActionPolicy decision
    /// Responder Chain proceeds querying a next Responder when `.next` policy decision is returned
    /// Modify `preferences` argument to set User Agent, Content Mode and disable javaScript
    @MainActor
    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy?

    /// Called only for Main Frame Navigation Actions when one of the Responders returned `.cancel` (with possible related actions) for `decidePolicy(for:navigationAction)` query before submitting the decision to Web View
    @MainActor
    func willCancel(_ navigationAction: NavigationAction, with relatedAction: NavigationActionCancellationRelatedAction)

    /// Called only for Main Frame Navigation Actions when one of the Responders returned `.cancel` (with possible related actions) for `decidePolicy(for:navigationAction)` query after submitting the decision to Web View
    @MainActor
    func didCancel(_ navigationAction: NavigationAction, with relatedAction: NavigationActionCancellationRelatedAction)

    // MARK: Navigation

    /// Called only for Main Frame Navigation Actions when all of the Responders returned `.next` or one of the Responders returned `.allow`  for `decidePolicy(for:navigationAction)` query
    @MainActor
    func willStart(_ navigationAction: NavigationAction)
    /// Called for `webView:didStartNavigation:` event _except_ for the navigations that were redirected, in this case `navigation(_:didReceive:redirect)` is called
    /// May be called without preceding `decidePolicy(for:navigationAction)` for Session Restoration navigations
    @MainActor
    func didStart(_ navigation: Navigation)

    /// Invoked when the web view needs to respond to an authentication challenge.
    @MainActor
    func didReceive(_ authenticationChallenge: URLAuthenticationChallenge, for navigation: Navigation?) async -> AuthChallengeDisposition?

    /// Happens after server redirects and completing authenticationChallenge
    /// Navigation Responders are queried in the provided order until any of them returns a NavigationResponsePolicy decision
    /// Responder Chain proceeds querying a next Responder when `.next` policy decision is returned
    @MainActor
    func decidePolicy(for navigationResponse: NavigationResponse, currentNavigation: Navigation?) async -> NavigationResponsePolicy?

    /// Now the Navigation is considered _happened_ and added to the BackForwardList as a Current Item
    @MainActor
    func didCommit(_ navigation: Navigation)

    /// Called _before_ `decidePolicy(for:navigationAction)` for navigations being redirected by server or client (js)
    @MainActor
    func navigation(_ navigation: Navigation, didReceive redirect: RedirectType)

    // MARK: - Completion

    /// Main Frame navigation did finish
    @MainActor
    func navigationDidFinish(_ navigation: Navigation)

    /// Called for both `webView:didFailNavigation:` and `webView:didFailProvisionalNavigation:` - check the `isProvisioned` to distinguish
    @MainActor
    func navigation(_ navigation: Navigation, didFailWith error: WKError, isProvisioned: Bool)

    /// Called when one of the Responders returned `.download` for `decidePolicy(for:navigationAction)` query
    /// Not followed by `navigationDidFinish` or `navigation(_:didFail:)` events
    @MainActor
    func navigationAction(_ navigationAction: NavigationAction, didBecome download: WebKitDownload)

    /// Called when one of the Responders returned `.download` for `decidePolicy(for:navigationResponse)` query
    /// Not followed by `navigationDidFinish` or `navigation(_:didFail:)` events
    @MainActor
    func navigationResponse(_ navigationResponse: NavigationResponse, didBecome download: WebKitDownload, currentNavigation: Navigation?)

    /// Called when WebView process was terminated
    /// Not followed by `navigationDidFinish` or `navigation(_:didFail:)` events
    @MainActor
    func webContentProcessDidTerminate(currentNavigation: Navigation?)

}

// MARK: - Delegate methods are optional
public extension NavigationResponder {

    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? { .next }

    func willCancel(_ navigationAction: NavigationAction, with relatedAction: NavigationActionCancellationRelatedAction) {}
    func didCancel(_ navigationAction: NavigationAction, with relatedAction: NavigationActionCancellationRelatedAction) {}


    func willStart(_ navigationAction: NavigationAction) {}
    func didStart(_ navigation: Navigation) {}

    @MainActor
    func didReceive(_ authenticationChallenge: URLAuthenticationChallenge, for navigation: Navigation?) async -> AuthChallengeDisposition? { .next }

    func decidePolicy(for navigationResponse: NavigationResponse, currentNavigation: Navigation?) async -> NavigationResponsePolicy? { .next }

    func didCommit(_ navigation: Navigation) {}
    func navigation(_ navigation: Navigation, didReceive redirect: RedirectType) {}

    func navigationDidFinish(_ navigation: Navigation) {}

    func navigation(_ navigation: Navigation, didFailWith error: WKError, isProvisioned: Bool) {}

    func navigationAction(_ navigationAction: NavigationAction, didBecome download: WebKitDownload) {}
    func navigationResponse(_ navigationResponse: NavigationResponse, didBecome download: WebKitDownload, currentNavigation: Navigation?) {}

    func webContentProcessDidTerminate(currentNavigation: Navigation?) {}

}
