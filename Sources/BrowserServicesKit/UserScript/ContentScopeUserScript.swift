//
//  ContentScopeUserScript.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import WebKit
import Combine

public final class ContentScopePreferences: Encodable {
    public let globalPrivacyControlValue: Bool
    public let debug: Bool = false
    public let sessionKey: String

    public init(gpcEnabled: Bool, sessionKey: String) {
        self.globalPrivacyControlValue = gpcEnabled
        self.sessionKey = sessionKey
    }
}

public final class ContentScopeUserScript: NSObject, UserScript {
    public let messageNames: [String] = []

    public init(_ privacyConfigManager: PrivacyConfigurationManager, preferences: ContentScopePreferences) {
        source = ContentScopeUserScript.generateSource(privacyConfigManager, preferences: preferences)
    }

    public static func generateSource(_ privacyConfigurationManager: PrivacyConfigurationManager, preferences: ContentScopePreferences) -> String {
        let privacyConfigJson = String(data: privacyConfigurationManager.currentConfig, encoding: .utf8)

        guard let json = try? JSONEncoder().encode(privacyConfigurationManager.privacyConfig.userUnprotectedDomains),
              let jsonString = String(data: json, encoding: .utf8),
              let jsonPreferences = try? JSONEncoder().encode(preferences),
              let jsonPreferencesString = String(data: jsonPreferences, encoding: .utf8)
              else {
            return ""
        }
        
        return loadJS("contentScope", from: Bundle.module, withReplacements: [
            "$CONTENT_SCOPE$": privacyConfigJson!,
            "$USER_UNPROTECTED_DOMAINS$": jsonString,
            "$USER_PREFERENCES$": jsonPreferencesString,
        ])
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    }

    public let source: String

    public let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    public let forMainFrameOnly: Bool = false
    public let requiresRunInPageContentWorld: Bool = true

}
