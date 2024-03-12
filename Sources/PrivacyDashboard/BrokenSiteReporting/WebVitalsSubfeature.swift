//
//  WebVitalsSubfeature.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import WebKit

public class WebVitalsSubfeature: Subfeature {

    public var messageOriginPolicy: MessageOriginPolicy = .all
    public var featureName: String = "webVitalsSubfeature"
    public var broker: UserScriptMessageBroker?

    var completionHandler: (([Double]?) -> Void)?

    public func handler(forMethodNamed methodName: String) -> Handler? {
        guard methodName == "vitalsResult" else { return nil }

        return vitalsResult
    }

    public func vitalsResult(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let payload = params as? [String:Any] else {
            completionHandler?(nil)
            return nil
        }

        completionHandler?(payload["vitals"] as? [Double])
        return nil
    }

    public func notifyHandler(from webView: WKWebView, handler: @escaping ([Double]?) -> Void) {
        completionHandler = handler
        broker?.push(method: "getVitals", params: nil, for: self, into: webView)
    }
}
