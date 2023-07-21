//
//  WKNavigationActionExtension.swift
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
import WebKit

// swiftlint:disable line_length
extension WKNavigationAction: WebViewNavigationAction {

    /// Safe Optional `sourceFrame: WKFrameInfo` getter:
    /// In this cruel reality the source frame IS Nullable for Developer-initiated load API calls (WKWebView.loadRequest or for a initial WebView navigation)
    /// https://github.com/WebKit/WebKit/blob/c39358705b79ccf2da3b76a8be6334e7e3dfcfa6/Source/WebKit/UIProcess/WebPageProxy.cpp#L5708
    public var safeSourceFrame: WKFrameInfo? {
        _=WKNavigationAction.addSafetyCheckForSafeSourceFrameUsageOnce
        return self.perform(#selector(getter: sourceFrame))?.takeUnretainedValue() as? WKFrameInfo
    }

#if DEBUG

    private static var ignoredSourceFrameUsageSymbols = Set<String>()

    // ensure `.safeSourceFrame` is used and not `.sourceFrame`
    static var addSafetyCheckForSafeSourceFrameUsageOnce: Void = {
        let originalSourceFrameMethod = class_getInstanceMethod(WKNavigationAction.self, #selector(getter: WKNavigationAction.sourceFrame))!
        let swizzledSourceFrameMethod = class_getInstanceMethod(WKNavigationAction.self, #selector(WKNavigationAction.swizzledSourceFrame))!
        method_exchangeImplementations(originalSourceFrameMethod, swizzledSourceFrameMethod)

        // ignore `sourceFrame` selector calls from `safeSourceFrame` itself
        ignoredSourceFrameUsageSymbols.insert(callingSymbol())
    }()

    @objc dynamic private func swizzledSourceFrame() -> WKFrameInfo? {
        func fileLine(file: StaticString = #file, line: Int = #line) -> String {
            return "\(("\(file)" as NSString).lastPathComponent):\(line + 1)"
        }

        // don‘t break twice
        if Self.ignoredSourceFrameUsageSymbols.insert(callingSymbol()).inserted {
            breakByRaisingSigInt("Don‘t use `WKNavigationAction.sourceFrame` as it has incorrect nullability\n" +
                                 "Use `WKNavigationAction.safeSourceFrame` instead")
        }

        return self.swizzledSourceFrame() // call the original
    }

#else
    static var addSafetyCheckForSafeSourceFrameUsageOnce: Void { () }
#endif

    // prevent exception if private API keys go missing
    open override func value(forUndefinedKey key: String) -> Any? {
        assertionFailure("valueForUndefinedKey: \(key)")
        return nil
    }

    @nonobjc public var shouldDownload: Bool {
        if #available(macOS 11.3, iOS 14.5, *) {
            return shouldPerformDownload
        }
        return self.value(forKey: "shouldPerformDownload") as? Bool ?? false
    }

#if _IS_USER_INITIATED_ENABLED
    @nonobjc public var isUserInitiated: Bool? {
        return self.value(forKey: "isUserInitiated") as? Bool
    }
#else
    public var isUserInitiated: Bool? {
        return nil
    }
#endif

#if _IS_REDIRECT_ENABLED
    @nonobjc public var isRedirect: Bool? {
        return self.value(forKey: "isRedirect") as? Bool
    }
#else
    public var isRedirect: Bool? {
        return nil
    }
#endif

#if _MAIN_FRAME_NAVIGATION_ENABLED
    @nonobjc public var mainFrameNavigation: WKNavigation? {
        return self.value(forKey: "mainFrameNavigation") as? WKNavigation
    }
#else
    public var mainFrameNavigation: WKNavigation? {
        return nil
    }
#endif

#if os(macOS)
    public var isMiddleClick: Bool {
        buttonNumber == 4
    }
#endif

    // associated NavigationAction wrapper for the WKNavigationAction
    private static let navigationActionKey = UnsafeRawPointer(bitPattern: "navigationActionKey".hashValue)!
    internal var navigationAction: NavigationAction? {
        get {
            objc_getAssociatedObject(self, Self.navigationActionKey) as? NavigationAction
        }
        set {
            objc_setAssociatedObject(self, Self.navigationActionKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
    /// returns navigation distance from current BackForwardList item for back/forward navigations
    /// -1-based, negative for back navigations; 1-based, positive for forward navigations
    public func getDistance(from historyItemIdentity: HistoryItemIdentity?) -> Int? {
        guard let historyItemIdentity,
              let backForwardList = (self.safeSourceFrame ?? self.targetFrame)?.webView?.backForwardList
        else { return nil }
        if backForwardList.backItem.map(HistoryItemIdentity.init) == historyItemIdentity {
            return 1
        } else if backForwardList.forwardItem.map(HistoryItemIdentity.init) == historyItemIdentity {
            return -1
        } else if let forwardIndex = backForwardList.forwardList.firstIndex(where: { $0.identity == historyItemIdentity }) {
            return -forwardIndex - 1 // going back from item in forward list to current, adding 1 to zero based index
        }
        let backList = backForwardList.backList
        if let backIndex = backList.lastIndex(where: { $0.identity == historyItemIdentity }) {
            return backList.count - backIndex  // going forward from item in _reveresed_ back list to current
        }
        return nil
    }
#endif

    public var isSameDocumentNavigation: Bool {
        guard let currentURL = targetFrame?.safeRequest?.url?.absoluteString,
              let newURL = self.request.url?.absoluteString,
              !currentURL.isEmpty,
              !newURL.isEmpty
        else { return false }

        switch navigationType {
        case .linkActivated, .other:
            return self.isRedirect != true && newURL.hashedSuffix != nil && currentURL.droppingHashedSuffix() == newURL.droppingHashedSuffix()
        case .backForward:
            return (newURL.hashedSuffix != nil || currentURL.hashedSuffix != nil) && currentURL.droppingHashedSuffix() == newURL.droppingHashedSuffix()
        case .reload, .formSubmitted, .formResubmitted:
            return false
        @unknown default:
            return false
        }
    }
}

extension WKNavigationActionPolicy {

    static let downloadPolicy: WKNavigationActionPolicy = {
        if #available(macOS 11.3, iOS 14.5, *) {
            return .download
        }
        return WKNavigationActionPolicy(rawValue: Self.allow.rawValue + 1) ?? .cancel
    }()

}
// swiftlint:enable line_length
