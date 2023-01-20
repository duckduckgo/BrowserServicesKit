//
//  WKErrorExtension.swift
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

private protocol WKErrorProtocol {
    var _isFrameLoadInterrupted: Bool { get }
}

extension WKError: WKErrorProtocol {

    public var failingUrl: URL? {
        return (self as NSError).userInfo[NSURLErrorFailingURLStringErrorKey] as? URL
    }

    public var isFrameLoadInterrupted: Bool { (self as WKErrorProtocol)._isFrameLoadInterrupted }
    // suppress deprecation warning
    @available(macOS, introduced: 10.3, deprecated: 10.14)
    fileprivate var _isFrameLoadInterrupted: Bool {
        let error = self as NSError
        return error.code == WebKitErrorFrameLoadInterruptedByPolicyChange && error.domain == WebKitErrorDomain
    }

    public var isNavigationCancelled: Bool {
        let error = self as NSError
        return error.code == NSURLErrorCancelled && error.domain == NSURLErrorDomain
    }

}

extension WKError: LocalizedError {

    public var errorDescription: String? {
        "<WKError \((self as NSError).domain) error \(code)\(self.failingUrl != nil ? "url: \"\(self.failingUrl!)\"" : "")>"
    }

}
