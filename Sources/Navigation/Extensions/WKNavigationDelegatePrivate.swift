//  WKNavigationDelegatePrivate.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

@objc public protocol WKNavigationDelegatePrivate: WKNavigationDelegate {

    @objc(_webView:didFinishLoadWithRequest:inFrame:)
    optional func webView(_ webView: WKWebView, didFinishLoadWith request: URLRequest, in frame: WKFrameInfo)

    @objc(_webView:didFailProvisionalLoadWithRequest:inFrame:withError:)
    optional func webView(_ webView: WKWebView, didFailProvisionalLoadWith request: URLRequest, in frame: WKFrameInfo, with error: Error)

    @objc(_webView:willPerformClientRedirectToURL:delay:)
    optional func webView(_ webView: WKWebView, willPerformClientRedirectTo url: URL, delay: TimeInterval)

    @objc(_webViewDidCancelClientRedirect:)
    optional func webViewDidCancelClientRedirect(_ webView: WKWebView)

    @objc(_webView:navigation:didSameDocumentNavigation:)
    optional func webView(_ webView: WKWebView, navigation: WKNavigation, didSameDocumentNavigation navigationType: Int)

    @objc(_webView:webContentProcessDidTerminateWithReason:)
    optional func webView(_ webView: WKWebView, webContentProcessDidTerminateWith reason: Int)

}
