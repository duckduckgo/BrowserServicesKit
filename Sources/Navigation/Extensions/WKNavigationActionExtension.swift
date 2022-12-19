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

import WebKit

extension WKNavigationAction: WebViewNavigationAction {

    var safeSourceFrame: WKFrameInfo? {
        // In this cruel reality the source frame IS Nullable pretty often
        withUnsafePointer(to: self.sourceFrame) { $0.withMemoryRebound(to: WKFrameInfo?.self, capacity: 1) { $0 } }.pointee
    }

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
    public var isUserInitiated: Bool {
        guard responds(to: NSSelectorFromString(Self._isUserInitiated)) else { return false }
        return self.value(forKey: Self._isUserInitiated) as? Bool ?? false
    }
#else
    public var isUserInitiated: Bool {
        false
    }
#endif

#if os(macOS)
    public var isMiddleClick: Bool {
        buttonNumber == 4
    }
#endif

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

}
