//
//  WebKitDownload.swift
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

@objc public protocol WebKitDownload: AnyObject, NSObjectProtocol {
    var originalRequest: URLRequest? { get }
    var webView: WKWebView? { get }
    var delegate: WKDownloadDelegate? { get set }
}

extension WebKitDownload {
    public func cancel(_ completionHandler: ((Data?) -> Void)? = nil) {
        if #available(macOS 11.3, iOS 14.5, *),
           let download = self as? WKDownload {

            download.cancel(completionHandler)
        } else {
            self.perform(#selector(Progress.cancel))
            completionHandler?(nil)
        }
    }
}

@available(macOS 11.3, iOS 14.5, *)
extension WKDownload: WebKitDownload {}
