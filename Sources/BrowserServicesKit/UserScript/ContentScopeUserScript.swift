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
import ContentScopeScripts

public final class ContentScopeProperties: Encodable {
    public let globalPrivacyControlValue: Bool
    public let debug: Bool = false
    public let sessionKey: String
    public let platform = ContentScopePlatform()
    public let features: [String: ContentScopeFeature]

    public init(gpcEnabled: Bool, sessionKey: String, featureToggles: ContentScopeFeatureToggles) {
        self.globalPrivacyControlValue = gpcEnabled
        self.sessionKey = sessionKey
        features = [
            "autofill": ContentScopeFeature(featureToggles: featureToggles)
        ]
    }
}
public struct ContentScopeFeature: Encodable {
    
    public let settings: [String: ContentScopeFeatureToggles]
    
    public init(featureToggles: ContentScopeFeatureToggles) {
        self.settings = ["featureToggles": featureToggles]
    }
}

public struct ContentScopeFeatureToggles: Encodable {

    public let emailProtection: Bool
    
    public let credentialsAutofill: Bool
    public let identitiesAutofill: Bool
    public let creditCardsAutofill: Bool
    
    public let credentialsSaving: Bool
    
    public let passwordGeneration: Bool
    
    public let inlineIconCredentials: Bool
    
    // Explicitly defined memberwise init only so it can be public
    public init(emailProtection: Bool,
                credentialsAutofill: Bool,
                identitiesAutofill: Bool,
                creditCardsAutofill: Bool,
                credentialsSaving: Bool,
                passwordGeneration: Bool,
                inlineIconCredentials: Bool) {
        
        self.emailProtection = emailProtection
        self.credentialsAutofill = credentialsAutofill
        self.identitiesAutofill = identitiesAutofill
        self.creditCardsAutofill = creditCardsAutofill
        self.credentialsSaving = credentialsSaving
        self.passwordGeneration = passwordGeneration
        self.inlineIconCredentials = inlineIconCredentials
    }
    
    enum CodingKeys: String, CodingKey {
        case emailProtection = "emailProtection"
        
        case credentialsAutofill = "inputType_credentials"
        case identitiesAutofill = "inputType_identities"
        case creditCardsAutofill = "inputType_creditCards"
    
        case credentialsSaving = "credentials_saving"
        
        case passwordGeneration = "password_generation"
        
        case inlineIconCredentials = "inlineIcon_credentials"
    }
}

public struct ContentScopePlatform: Encodable {
    #if os(macOS)
    let name = "macos"
    #elseif os(iOS)
    let name = "ios"
    #else
    let name = "unknown"
    #endif
}

public final class ContentScopeUserScript: NSObject, UserScript {
    public let messageNames: [String] = []

    public init(_ privacyConfigManager: PrivacyConfigurationManaging, properties: ContentScopeProperties) {
        source = ContentScopeUserScript.generateSource(privacyConfigManager, properties: properties)
    }

    public static func generateSource(_ privacyConfigurationManager: PrivacyConfigurationManaging, properties: ContentScopeProperties) -> String {

        guard let privacyConfigJson = String(data: privacyConfigurationManager.currentConfig, encoding: .utf8),
              let userUnprotectedDomains = try? JSONEncoder().encode(privacyConfigurationManager.privacyConfig.userUnprotectedDomains),
              let userUnprotectedDomainsString = String(data: userUnprotectedDomains, encoding: .utf8),
              let jsonProperties = try? JSONEncoder().encode(properties),
              let jsonPropertiesString = String(data: jsonProperties, encoding: .utf8)
              else {
            return ""
        }
        
        return loadJS("contentScope", from: ContentScopeScripts.Bundle, withReplacements: [
            "$CONTENT_SCOPE$": privacyConfigJson,
            "$USER_UNPROTECTED_DOMAINS$": userUnprotectedDomainsString,
            "$USER_PREFERENCES$": jsonPropertiesString
        ])
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    }

    public let source: String

    public let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    public let forMainFrameOnly: Bool = false
    public let requiresRunInPageContentWorld: Bool = true

}
