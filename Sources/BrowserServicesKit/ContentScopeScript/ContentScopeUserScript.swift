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
import UserScript
import os.log

public final class ContentScopeProperties: Encodable {
    public let globalPrivacyControlValue: Bool
    public let debug: Bool = false
    public let sessionKey: String
    public let platform = ContentScopePlatform()
    public let features: [String: ClickToLoad]

    public init(gpcEnabled: Bool, sessionKey: String, featureToggles: ContentScopeFeatureToggles) {
        self.globalPrivacyControlValue = gpcEnabled
        self.sessionKey = sessionKey

        let clickToLoad = ClickToLoad(
            exceptions: [],
            settings: ClickToLoad.Settings(
                facebookInc: ClickToLoad.Settings.Rule(ruleActions: ["block-ctl-fb"], state: "enabled"),
                youtube: ClickToLoad.Settings.Rule(ruleActions: ["block-ctl-yt"], state: "disabled")
            ),
            state: "enabled",
            hash: "be4a32a8303eb523dbc0efe89deaa34d"
        )


        features = [
//            "autofill": ContentScopeFeature(featureToggles: featureToggles),
            "clickToLoad": clickToLoad
        ]
    }
}

public struct ClickToLoad: Encodable {
    struct Settings: Encodable {
        struct Rule: Encodable {
            let ruleActions: [String]
            let state: String
        }
        let facebookInc: Rule
        let youtube: Rule

        private enum CodingKeys: String, CodingKey {
            case facebookInc = "Facebook, Inc."
            case youtube = "Youtube"
        }
    }

    let exceptions: [String]
    let settings: Settings
    let state: String
    let hash: String
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
    public let thirdPartyCredentialsProvider: Bool
    
    // Explicitly defined memberwise init only so it can be public
    public init(emailProtection: Bool,
                credentialsAutofill: Bool,
                identitiesAutofill: Bool,
                creditCardsAutofill: Bool,
                credentialsSaving: Bool,
                passwordGeneration: Bool,
                inlineIconCredentials: Bool,
                thirdPartyCredentialsProvider: Bool) {
        
        self.emailProtection = emailProtection
        self.credentialsAutofill = credentialsAutofill
        self.identitiesAutofill = identitiesAutofill
        self.creditCardsAutofill = creditCardsAutofill
        self.credentialsSaving = credentialsSaving
        self.passwordGeneration = passwordGeneration
        self.inlineIconCredentials = inlineIconCredentials
        self.thirdPartyCredentialsProvider = thirdPartyCredentialsProvider
    }
    
    enum CodingKeys: String, CodingKey {
        case emailProtection = "emailProtection"
        
        case credentialsAutofill = "inputType_credentials"
        case identitiesAutofill = "inputType_identities"
        case creditCardsAutofill = "inputType_creditCards"
    
        case credentialsSaving = "credentials_saving"
        
        case passwordGeneration = "password_generation"
        
        case inlineIconCredentials = "inlineIcon_credentials"
        case thirdPartyCredentialsProvider = "third_party_credentials_provider"
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

public final class ContentScopeUserScript: NSObject, UserScript, WKScriptMessageHandlerWithReply {

    public weak var webView: WKWebView?

    public let messageNames: [String] = ["getClickToLoadState", "unblockClickToLoadContent"]

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
        os_log("Message received: %s", log: .userScripts, type: .debug, String(describing: message.body))
    }

    @MainActor
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
        os_log("Message received: %s", log: .userScripts, type: .debug, String(describing: message.body))
        if message.name == "getClickToLoadState" {
//            let js = "window.postMessage({ ruleAction: block });"
//            let js = """
//                window.clickToLoadMessageCallback(\("{ \"devMode\": true, \"youtubePreviewsEnabled\": false }"));
//            """
            let js = "console.log(typeof window.clickToLoadMessageCallback)"
            evaluate(js: js)
        } else if message.name == "" {
            let js = "window.clickToLoadMessageCallback(\("{ devMode: true, youtubePreviewsEnabled: false }"))"
            evaluate(js: js)
        }

        return (nil, nil)
    }

    public func displayClickToLoadPlaceholders() {
        let js = "window.displayClickToLoadPlaceholders({ \"ruleAction\": [\"block\"] });"
        evaluate(js: js)
    }

    private func evaluate(js: String) {
        guard let webView else {
            assertionFailure("WebView not set")
            return
        }
        webView.evaluateJavaScript(js, in: nil, in: WKContentWorld.defaultClient)
    }

    public let source: String

    public let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    public let forMainFrameOnly: Bool = false
    public let requiresRunInPageContentWorld: Bool = true

}
