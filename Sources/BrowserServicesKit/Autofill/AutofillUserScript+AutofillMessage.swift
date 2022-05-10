//
//  AutofillUserScript+AutofillMessage.swift
//  DuckDuckGo
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

protocol AutofillMessage {
    var messageName: String { get }
    var messageBody: Any { get }
    var messageHost: String { get }
    var isMainFrame: Bool { get }
    var messageWebView: WKWebView? { get }
}

extension WKScriptMessage: AutofillMessage {
    var messageName: String {
        return name
    }
    
    var messageBody: Any {
        return body
    }
    
    var messageHost: String {
        return frameInfo.securityOrigin.host
    }

    var isMainFrame: Bool {
        return frameInfo.isMainFrame
    }
    
    var messageWebView: WKWebView? {
        return webView
    }
}
