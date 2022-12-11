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
        // In this cruel reality the source frame IS Nullable for initial load events
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

    public var currentHistoryItemIdentity: HistoryItemIdentity? {
        guard let currentItem = self.safeSourceFrame?.webView?.backForwardList.currentItem else { return nil }
        return HistoryItemIdentity(currentItem)
    }

}
