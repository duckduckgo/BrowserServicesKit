//
//  WKErrorExtension.swift
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

import Common
import WebKit

extension WKError {

    public var failingUrl: URL? {
        return _nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? URL
    }

    public var isFrameLoadInterrupted: Bool {
        code == .frameLoadInterruptedByPolicyChange && _nsError.domain == WKError.WebKitErrorDomain
    }

    public var isNavigationCancelled: Bool {
        code.rawValue == NSURLErrorCancelled && _nsError.domain == NSURLErrorDomain
    }

}

private protocol WKErrorProtocol {
    static var _WebKitErrorDomain: String { get }
}

extension WKError: WKErrorProtocol {

    // suppress WebKit.WebKitErrorDomain deprecation warning
    @available(macOS, introduced: 10.3, deprecated: 10.14)
    fileprivate static var _WebKitErrorDomain: String {
#if os(macOS)
        assert(WebKit.WebKitErrorDomain == "WebKitErrorDomain")
        return WebKit.WebKitErrorDomain
#else
        return "WebKitErrorDomain"
#endif
    }
    static var WebKitErrorDomain: String { (self as WKErrorProtocol.Type)._WebKitErrorDomain }

}

extension WKError.Code {
#if os(macOS)
    static let frameLoadInterruptedByPolicyChange: WKError.Code = {
        assert(WebKitErrorFrameLoadInterruptedByPolicyChange == 102)
        return WKError.Code(rawValue: WebKitErrorFrameLoadInterruptedByPolicyChange)!
    }()
#else
    static let frameLoadInterruptedByPolicyChange = WKError.Code(rawValue: 102)!
#endif
}

extension WKError: LocalizedError {

    public var errorDescription: String? {
        "<WKError \((self as NSError).domain) error \(code.rawValue) \"\(self.localizedDescription)\"" +
        "\(self.failingUrl != nil ? " url: \"\(self.failingUrl!)\"" : "")>"
    }

}
