//
//  SSLErrorPageUserScript.swift
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

public protocol SSLErrorPageUserScriptDelegate: AnyObject {

    func leaveSite()
    func visitSite()

}

public final class SSLErrorPageUserScript: NSObject, Subfeature {

    enum MessageName: String, CaseIterable {

        case leaveSite
        case visitSite

    }

    public let messageOriginPolicy: MessageOriginPolicy = .all
    public let featureName: String = "sslErrorPage"

    public var isEnabled: Bool = false
    public var failingURL: URL?

    public weak var broker: UserScriptMessageBroker?
    public weak var delegate: SSLErrorPageUserScriptDelegate?

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    @MainActor
    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
//        guard isEnabled else { return nil }
        switch MessageName(rawValue: methodName) {
        case .leaveSite:
            return handleLeaveSiteAction
        case .visitSite:
            return handleVisitSiteAction
        default:
            assertionFailure("SSLErrorPageUserScript: Failed to parse User Script message: \(methodName)")
            return nil
        }
    }

    @MainActor
    func handleLeaveSiteAction(params: Any, message: UserScriptMessage) -> Encodable? {
        delegate?.leaveSite()
        return nil
    }

    @MainActor
    func handleVisitSiteAction(params: Any, message: UserScriptMessage) -> Encodable? {
        delegate?.visitSite()
        return nil
    }

}

