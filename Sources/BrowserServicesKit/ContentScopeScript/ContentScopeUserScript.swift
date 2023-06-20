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
import Common
import os.log

public final class ContentScopeProperties: Encodable {
    public let globalPrivacyControlValue: Bool
    public let debug: Bool = false
    public let sessionKey: String
    public let platform = ContentScopePlatform()
    public let features: [String: ClickToLoad]
//    public let features: [String: ContentScopeFeature]

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
    public let emailProtectionIncontextSignup: Bool

    public let credentialsAutofill: Bool
    public let identitiesAutofill: Bool
    public let creditCardsAutofill: Bool

    public let credentialsSaving: Bool

    public let passwordGeneration: Bool

    public let inlineIconCredentials: Bool
    public let thirdPartyCredentialsProvider: Bool

    // Explicitly defined memberwise init only so it can be public
    public init(emailProtection: Bool,
                emailProtectionIncontextSignup: Bool,
                credentialsAutofill: Bool,
                identitiesAutofill: Bool,
                creditCardsAutofill: Bool,
                credentialsSaving: Bool,
                passwordGeneration: Bool,
                inlineIconCredentials: Bool,
                thirdPartyCredentialsProvider: Bool) {

        self.emailProtection = emailProtection
        self.emailProtectionIncontextSignup = emailProtectionIncontextSignup
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
        case emailProtectionIncontextSignup = "emailProtection_incontext_signup"

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

//public final class ContentScopeUserScript: NSObject, UserScript, WKScriptMessageHandlerWithReply {
//
//    public weak var webView: WKWebView?
//
//    public let messageNames: [String] = ["getClickToLoadState", "unblockClickToLoadContent"]
//=======
public final class ContentScopeUserScript: NSObject, UserScript, UserScriptMessaging {
//>>>>>>> main

    public var broker: UserScriptMessageBroker
    public let isIsolated: Bool
    public var messageNames: [String] = []

    public init(_ privacyConfigManager: PrivacyConfigurationManaging,
                properties: ContentScopeProperties,
                isIsolated: Bool = false
    ) {
        self.isIsolated = isIsolated
        let contextName = self.isIsolated ? "contentScopeScriptsIsolated" : "contentScopeScripts";

        broker = UserScriptMessageBroker(context: contextName)

        // dont register any handlers at all if we're not in the isolated context
        messageNames = isIsolated ? [contextName] : []

        source = ContentScopeUserScript.generateSource(
                privacyConfigManager,
                properties: properties,
                isolated: isIsolated,
                config: broker.messagingConfig()
        )
    }

    public static func generateSource(_ privacyConfigurationManager: PrivacyConfigurationManaging,
                                      properties: ContentScopeProperties,
                                      isolated: Bool,
                                      config: WebkitMessagingConfig
    ) -> String {

        guard let privacyConfigJson = String(data: privacyConfigurationManager.currentConfig, encoding: .utf8),
              let userUnprotectedDomains = try? JSONEncoder().encode(privacyConfigurationManager.privacyConfig.userUnprotectedDomains),
              let userUnprotectedDomainsString = String(data: userUnprotectedDomains, encoding: .utf8),
              let jsonProperties = try? JSONEncoder().encode(properties),
              let jsonPropertiesString = String(data: jsonProperties, encoding: .utf8),
              let jsonConfig = try? JSONEncoder().encode(config),
              let jsonConfigString = String(data: jsonConfig, encoding: .utf8)
        else {
            return ""
        }

        let jsInclude = isolated ? "contentScopeIsolated" : "contentScope"

        return loadJS(jsInclude, from: ContentScopeScripts.Bundle, withReplacements: [
            "$CONTENT_SCOPE$": privacyConfigJson,
            "$USER_UNPROTECTED_DOMAINS$": userUnprotectedDomainsString,
            "$USER_PREFERENCES$": jsonPropertiesString,
            "$WEBKIT_MESSAGING_CONFIG$": jsonConfigString
        ])
    }

//    @MainActor
//    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
//        os_log("Message received: %s", log: .userScripts, type: .debug, String(describing: message.body))
//    }
//
//    @MainActor
//    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
//        os_log("Message received: %s", log: .userScripts, type: .debug, String(describing: message.body))
//        if message.name == "getClickToLoadState" {
//            let msg = [
//                "messageType": "response",
//                "responseMessageType": "getClickToLoadState",
//                "response": [
//                    "devMode": true,
//                    "youtubePreviewsEnabled": false
//                ]
//            ] as [String : Any]
//            let messageData = try! JSONSerialization.data(withJSONObject: msg)
//            let messageJSONString = String(data: messageData, encoding: .utf8)!
//            let js = "window.clickToLoadMessageCallback(\(messageJSONString));"
//            evaluate(js: js)
//
//            displayClickToLoadPlaceholders()
//        }
//
//        return (nil, nil)
//    }

//    public func displayClickToLoadPlaceholders() {
//        let message = [
//            "messageType": "displayClickToLoadPlaceholders",
//            "options": [
//                "ruleAction": ["block"]
//            ]
//        ] as [String : Any]
//        let messageData = try! JSONSerialization.data(withJSONObject: message)
//        let messageJSONString = String(data: messageData, encoding: .utf8)!
//        let js = "window.clickToLoadMessageCallback(\(messageJSONString));"
//        evaluate(js: js)
//    }
//
//    private func evaluate(js: String) {
//        guard let webView else {
//            assertionFailure("WebView not set")
//            return
//        }
////        webView.evaluateJavaScript(js, in: nil, in: .page)
//    }

    public let source: String
    public let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    public let forMainFrameOnly: Bool = false
    public var requiresRunInPageContentWorld: Bool { !self.isIsolated }
}

@available(macOS 11.0, iOS 14.0, *)
extension ContentScopeUserScript: WKScriptMessageHandlerWithReply {
    public func userContentController(_ userContentController: WKUserContentController,
                                      didReceive message: WKScriptMessage) async -> (Any?, String?) {
        let action = broker.messageHandlerFor(message)
        do {
            let json = try await broker.execute(action: action, original: message)
            return (json, nil)
        } catch {
            // forward uncaught errors to the client
            return (nil, error.localizedDescription)
        }
    }
}

// MARK: - Fallback for macOS 10.15
extension ContentScopeUserScript: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // unsupported
    }
}
