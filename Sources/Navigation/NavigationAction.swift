//
//  NavigationAction.swift
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

import Common
import Foundation
import WebKit

// swiftlint:disable line_length

public struct MainFrame {
    fileprivate init() {}
}

public struct NavigationAction {

    private static var maxIdentifier: UInt64 = 0
#if DEBUG
    static func resetIdentifier() { maxIdentifier = 0 }
#endif

    public var identifier: UInt64 = {
        Self.maxIdentifier += 1
        return Self.maxIdentifier
    }()

    public let request: URLRequest

    public let navigationType: NavigationType
#if os(macOS)
    public internal(set) var modifierFlags: NSEvent.ModifierFlags = []
#endif

#if _IS_USER_INITIATED_ENABLED
    public let isUserInitiated: Bool
#endif
    public let shouldDownload: Bool

    /// The frame requesting the navigation
    public let sourceFrame: FrameInfo
    /// The target frame, `nil` if this is a new window navigation
    public let targetFrame: FrameInfo?

    /// Used to protect main frame .redirect NavigationActionPolicy actions as only main frame can be redirected
    /// `nil` for non-main-frame navigations
    public var mainFrameTarget: MainFrame? {
        guard targetFrame?.isMainFrame == true else { return nil }
        return MainFrame()
    }

    /// Currently active Main Frame Navigation associated with the NavigationAction
    /// May be non-nil for non-main-frame NavigationActions
    public internal(set) weak var mainFrameNavigation: Navigation?

    /// Actual `BackForwardListItem` identity before the NavigationAction had started
    public let fromHistoryItemIdentity: HistoryItemIdentity?
    /// Previous Navigation Actions received during current logical `Navigation`, zero-based, most recent is the last
    public let redirectHistory: [NavigationAction]?

    public init(request: URLRequest, navigationType: NavigationType, currentHistoryItemIdentity: HistoryItemIdentity?, redirectHistory: [NavigationAction]?, isUserInitiated: Bool?, sourceFrame: FrameInfo, targetFrame: FrameInfo?, shouldDownload: Bool, mainFrameNavigation: Navigation?) {
        var request = request
        if request.allHTTPHeaderFields == nil {
            request.allHTTPHeaderFields = [:]
        }
        if request.url == nil {
            request.url = .empty
        }
        self.request = request
        self.navigationType = navigationType
#if _IS_USER_INITIATED_ENABLED
        self.isUserInitiated = isUserInitiated ?? false
#endif
        self.shouldDownload = shouldDownload

        self.sourceFrame = sourceFrame
        self.targetFrame = targetFrame

        self.fromHistoryItemIdentity = currentHistoryItemIdentity
        self.redirectHistory = redirectHistory
        self.mainFrameNavigation = mainFrameNavigation
    }

    internal init(webView: WKWebView, navigationAction: WKNavigationAction, currentHistoryItemIdentity: HistoryItemIdentity?, redirectHistory: [NavigationAction]?, navigationType: NavigationType? = nil, mainFrameNavigation: Navigation?) {
        // In this cruel reality the source frame IS Nullable for developer-initiated load events, this would mean we‘re targeting the main frame
        let sourceFrame = (navigationAction.safeSourceFrame ?? navigationAction.targetFrame).map(FrameInfo.init) ?? .mainFrame(for: webView)
        var navigationType = navigationType

        if case .other = navigationAction.navigationType,
           case .returnCacheDataElseLoad = navigationAction.request.cachePolicy,
           navigationType == nil,
           redirectHistory == nil,
           navigationAction.safeSourceFrame == nil,
           navigationAction.targetFrame?.isMainFrame == true,
           navigationAction.targetFrame?.safeRequest?.url?.isEmpty == true,
           webView.backForwardList.currentItem != nil {

            // go back after failing session restoration has `other` Navigation Type
            if let currentHistoryItemIdentity,
               let distance = navigationAction.getDistance(from: currentHistoryItemIdentity) {

                navigationType = .backForward(distance: distance)

            // session restoration
            } else if navigationAction.isUserInitiated != true,
                      currentHistoryItemIdentity == nil {
                navigationType = .sessionRestoration
            }
        }

        self.init(request: navigationAction.request,
                  navigationType: navigationType ?? NavigationType(navigationAction, currentHistoryItemIdentity: currentHistoryItemIdentity),
                  currentHistoryItemIdentity: currentHistoryItemIdentity,
                  redirectHistory: redirectHistory,
                  isUserInitiated: navigationAction.isUserInitiated,
                  sourceFrame: sourceFrame,
                  // always has targetFrame if not targeting to a new window
                  targetFrame: navigationAction.targetFrame.map(FrameInfo.init),
                  shouldDownload: navigationAction.shouldDownload,
                  mainFrameNavigation: mainFrameNavigation)
#if os(macOS)
        self.modifierFlags = navigationAction.modifierFlags
#endif
    }

    internal static func sessionRestoreNavigation(webView: WKWebView, mainFrameNavigation: Navigation?) -> Self {
        assert(webView.backForwardList.currentItem == nil)
        return self.init(request: URLRequest(url: webView.url ?? .empty), navigationType: .sessionRestoration, currentHistoryItemIdentity: nil, redirectHistory: nil, isUserInitiated: false, sourceFrame: .mainFrame(for: webView), targetFrame: .mainFrame(for: webView), shouldDownload: false, mainFrameNavigation: mainFrameNavigation)
    }

}

public extension NavigationAction {

    var isForMainFrame: Bool {
        targetFrame?.isMainFrame == true
    }

    var isTargetingNewWindow: Bool {
        sourceFrame.identity.webView != targetFrame?.identity.webView
    }

    var url: URL {
        request.url ?? .empty
    }

}

public struct NavigationPreferences: Equatable {

    public var userAgent: String?
    public var contentMode: WKWebpagePreferences.ContentMode

    fileprivate var javaScriptEnabledValue: Bool
    @available(macOS 11.0, iOS 14.0, *)
    public var javaScriptEnabled: Bool {
        get {
            javaScriptEnabledValue
        }
        set {
            javaScriptEnabledValue = newValue
        }
    }

    public static let `default` = NavigationPreferences(userAgent: nil, contentMode: .recommended, javaScriptEnabled: true)

    public init(userAgent: String?, contentMode: WKWebpagePreferences.ContentMode, javaScriptEnabled: Bool) {
        self.userAgent = userAgent
        self.contentMode = contentMode
        self.javaScriptEnabledValue = javaScriptEnabled
    }

    internal init(userAgent: String?, preferences: WKWebpagePreferences) {
        self.contentMode = preferences.preferredContentMode
        if #available(macOS 11.0, iOS 14.0, *) {
            self.javaScriptEnabledValue = preferences.allowsContentJavaScript
        } else {
            self.javaScriptEnabledValue = true
        }
    }

    internal func applying(to preferences: WKWebpagePreferences) -> WKWebpagePreferences {
        preferences.preferredContentMode = contentMode
        if #available(macOS 11.0, iOS 14.0, *) {
            preferences.allowsContentJavaScript = javaScriptEnabled
        }
        return preferences
    }

}

public enum NavigationActionPolicy {
    case allow
    case cancel
    case download
    case redirect(MainFrame, (Navigator) -> Void)
}

extension NavigationActionPolicy? {
    /// Pass decision making to next responder
    public static let next = NavigationActionPolicy?.none
}

extension NavigationActionPolicy? {
    public var debugDescription: String {
        if case .some(let policy) = self {
            return policy.debugDescription
        }
        return "next"
    }
}

extension NavigationAction: CustomDebugStringConvertible {
    public var debugDescription: String {
#if _IS_USER_INITIATED_ENABLED
        let isUserInitiatedStr = isUserInitiated ? " [user-initiated]" : ""
#else
        let isUserInitiatedStr = ""
#endif
        return "<NavigationAction #\(identifier)\(isUserInitiatedStr): url: \"\(url.absoluteString)\" type: \(navigationType.debugDescription)\(shouldDownload ? " Download" : "") frame: \(sourceFrame != targetFrame ? sourceFrame.debugDescription + " -> " : "")\(targetFrame.debugDescription)>"
    }
}

extension NavigationActionPolicy: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .allow: return "allow"
        case .cancel: return "cancel"
        case .download: return "download"
        case .redirect: return "redirect"
        }
    }
}

extension NavigationPreferences: CustomDebugStringConvertible {
    public var debugDescription: String {
        "\(userAgent ?? "")\(contentMode == .recommended ? "" : (contentMode == .mobile ? ":mobile" : "desktop"))\(javaScriptEnabledValue == false ? ":jsdisabled" : "")"
    }
}
