//
//  ClickToLoadUserScript.swift
//  DuckDuckGo
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

import Foundation
import UserScript
import Common
import WebKit

public final class ClickToLoadUserScript: Subfeature {

    public weak var broker: UserScriptMessageBroker?
    public weak var webView: WKWebView?

    public let messageOriginPolicy: MessageOriginPolicy = .all
    public let featureName: String = "clickToLoad"

    private var shouldBlockCTL = true

    public init() {}

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    // MARK: - MessageNames

    enum MessageNames: String, CaseIterable {
        case getClickToLoadState
        case displayClickToLoadPlaceholders
        case unblockClickToLoadContent
    }

    public func handler(forMethodNamed methodName: String) -> Handler? {
        switch MessageNames(rawValue: methodName) {
        case .getClickToLoadState:
            return handleGetClickToLoadState
        case .unblockClickToLoadContent:
            return handleUnblockClickToLoadContent
        default:
            assertionFailure("ClickToLoadUserScript: Failed to parse User Script message: \(methodName)")
            return nil
        }
    }

    private func handleGetClickToLoadState(params: Any, message: UserScriptMessage) -> Encodable? {
        [
            "devMode": true,
            "youtubePreviewsEnabled": false
        ]
    }

    private func handleUnblockClickToLoadContent(params: Any, message: UserScriptMessage) -> Encodable? {
        shouldBlockCTL = false
        webView?.reload()
        return nil
    }

    public func displayClickToLoadPlaceholders() {
        if let webView = webView {
            broker?.push(method: MessageNames.displayClickToLoadPlaceholders.rawValue, params: ["ruleAction": ["block"]], for: self, into: webView)
        }
    }

    
}
