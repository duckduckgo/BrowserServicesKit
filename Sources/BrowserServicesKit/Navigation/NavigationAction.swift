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

public struct NavigationAction: Equatable {

    @Debug.Value private static var maxIdentifier: UInt64 = 0
    @Debug.Value public var identifier: UInt64 = ++Self.maxIdentifier

    public let navigationType: NavigationType
    public let request: URLRequest

    public let sourceFrame: FrameInfo
    public let targetFrame: FrameInfo

    public let shouldDownload: Bool

    public var isForMainFrame: Bool {
        targetFrame.isMainFrame
    }

    public var isTargetingNewWindow: Bool {
        sourceFrame.isSharingWebView(with: targetFrame)
    }

    public var isUserInitiated: Bool {
        navigationType.isUserInitiated
    }

    public var url: URL {
        request.url!
    }

    internal init(navigationType: NavigationType, request: URLRequest, sourceFrame: FrameInfo, targetFrame: FrameInfo, shouldDownload: Bool) {
        self.navigationType = navigationType
        self.request = request
        self.sourceFrame = sourceFrame
        self.targetFrame = targetFrame
        self.shouldDownload = shouldDownload
    }

    internal init(_ navigationAction: WKNavigationAction, navigationType: NavigationType? = nil) {
        // In this cruel reality the source frame IS Nullable for initial load events
        let sourceFrame = (navigationAction.safeSourceFrame ?? navigationAction.targetFrame).map(FrameInfo.init) ?? .main

        self.init(navigationType: navigationType ?? NavigationType(navigationAction),
                  request: navigationAction.request,
                  sourceFrame: sourceFrame,
                  // always has targetFrame if not targeting to a new window
                  targetFrame: navigationAction.targetFrame.map(FrameInfo.init) ?? sourceFrame,
                  shouldDownload: navigationAction.shouldDownload)
    }

    internal static func sessionRestoreNavigation(url: URL) -> Self {
        self.init(navigationType: .sessionRestoration, request: URLRequest(url: url), sourceFrame: .main, targetFrame: .main, shouldDownload: false)
    }

}

public struct NavigationPreferences: Equatable {
    public var userAgent: String?
    public var contentMode: WKWebpagePreferences.ContentMode
    private var _javaScriptEnabled: Bool

    @available(macOS 11.0, iOS 14.0, *)
    public var javaScriptEnabled: Bool {
        get {
            _javaScriptEnabled
        }
        set {
            _javaScriptEnabled = newValue
        }
    }

    internal init(userAgent: String?, preferences: WKWebpagePreferences) {
        self.contentMode = preferences.preferredContentMode
        if #available(macOS 11.0, iOS 14.0, *) {
            self._javaScriptEnabled = preferences.allowsContentJavaScript
        } else {
            self._javaScriptEnabled = true
        }
    }

    internal func export(to preferences: WKWebpagePreferences) {
        preferences.preferredContentMode = contentMode
        if #available(macOS 11.0, iOS 14.0, *) {
            preferences.allowsContentJavaScript = javaScriptEnabled
        }
    }

}

public enum NavigationActionPolicy {
    case allow
    case cancel(with: NavigationActionCancellationRelatedAction)
    case download

    public static var cancel: NavigationActionPolicy = .cancel(with: .none)
}

extension NavigationActionPolicy? {
    /// Pass decision making to next responder
    public static let next = NavigationActionPolicy?.none
}

public enum NavigationActionCancellationRelatedAction : Equatable{
    case none
    case taskCancelled
    case redirect(URLRequest)
    case other(UserInfo)
}

extension WKNavigationAction {
#if _SHOULD_PERFORM_DOWNLOAD_ENABLED
    private static let _shouldPerformDownload = "_shouldPerformDownload"
#endif
    var shouldDownload: Bool {
        if #available(macOS 11.3, iOS 14.5, *) {
            return shouldPerformDownload
        }
#if _SHOULD_PERFORM_DOWNLOAD_ENABLED
        return self.value(forKey: Self._shouldPerformDownload) as? Bool ?? false
#else
        return false
#endif
    }

#if _IS_USER_INITIATED_ENABLED
    private static let _isUserInitiated = "_isUserInitiated"
    var isUserInitiated: Bool {
        guard responds(to: NSSelectorFromString(Self._isUserInitiated)) else { return false }
        return self.value(forKey: Self._isUserInitiated) as? Bool ?? false
    }
#else
    var isUserInitiated: Bool {
        false
    }
#endif

    var safeSourceFrame: WKFrameInfo? {
        // In this cruel reality the source frame IS Nullable for initial load events
        withUnsafePointer(to: self.sourceFrame) { $0.withMemoryRebound(to: WKFrameInfo?.self, capacity: 1) { $0 } }.pointee
    }

#if os(macOS)
    var isMiddleClick: Bool {
        buttonNumber == 4
    }
#endif
}

extension WKNavigationActionPolicy {
    public static let download = WKNavigationActionPolicy(rawValue: Self.allow.rawValue + 1) ?? .cancel
}
extension WKNavigationResponsePolicy {
    public static let download = WKNavigationResponsePolicy(rawValue: Self.allow.rawValue + 1) ?? .cancel
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
        "<NavigationAction #\(identifier): url: \"\(url.absoluteString)\" type: \(navigationType.debugDescription)\(shouldDownload ? " Download" : "") frame: \(sourceFrame != targetFrame ? sourceFrame.debugDescription + " -> " : "")\(targetFrame.debugDescription)>"
    }
}

extension NavigationActionPolicy: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .allow: return "allow"
        case .cancel(let action): return "cancel\((action.debugDescription.isEmpty ? "" : ":") + action.debugDescription)"
        case .download: return "download"
        }
    }
}

extension NavigationActionCancellationRelatedAction: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .none: return ""
        case .taskCancelled: return "taskCancelled"
        case .redirect(let request): return "redirect(\(request.url!)"
        case .other(let userInfo): return "other(\(userInfo.debugDescription))"
        }
    }
}
