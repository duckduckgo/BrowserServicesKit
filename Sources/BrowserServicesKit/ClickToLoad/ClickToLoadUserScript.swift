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

protocol ClickToLoadUserScriptDelegate: AnyObject {

}

public final class ClickToLoadUserScript: Subfeature {

    weak public var broker: UserScriptMessageBroker?
    weak var delegate: ClickToLoadUserScriptDelegate?
    weak var webView: WKWebView?

    public let messageOriginPolicy: MessageOriginPolicy = .all
    public let featureName: String = "clickToLoad"

    public init() {
        
    }

    // MARK: - Subfeature

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    // MARK: - MessageNames

    enum MessageNames: String, CaseIterable {
        case getClickToLoadState
        case displayClickToLoadPlaceholders
    }

    public func handler(forMethodNamed methodName: String) -> Handler? {
        switch MessageNames(rawValue: methodName) {
        case .getClickToLoadState:
            return nil
        default:
            assertionFailure("YoutubeOverlayUserScript: Failed to parse User Script message: \(methodName)")
            return nil
        }
    }

    private func handleGetClickToLoadState(params: Any, message: UserScriptMessage) -> Encodable? {
        nil
    }

    
}
