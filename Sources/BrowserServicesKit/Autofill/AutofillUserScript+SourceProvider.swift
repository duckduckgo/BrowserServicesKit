//
//  AutofillUserScript+SourceProvider.swift
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
import Autofill

public protocol AutofillUserScriptSourceProvider {
    var source: String { get }
}

public class DefaultAutofillSourceProvider: AutofillUserScriptSourceProvider {

    private struct ProviderData {
        var privacyConfig: Data
        var userUnprotectedDomains: Data
        var userPreferences: Data
    }

    let privacyConfigurationManager: PrivacyConfigurationManaging
    let properties: ContentScopeProperties
    private var sourceStr: String = ""

    public var source: String {
        return sourceStr
    }

    public init(privacyConfigurationManager: PrivacyConfigurationManaging, properties: ContentScopeProperties) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.properties = properties
    }

    public func loadJS() {
        guard let replacements = buildReplacementsString() else {
            sourceStr = ""
            return
        }
        sourceStr = AutofillUserScript.loadJS("assets/autofill", from: Autofill.bundle, withReplacements: replacements)
    }

    public func buildRuntimeConfigResponse() -> String? {
        guard let providerData = buildReplacementsData(),
              let privacyConfigJson = String(data: providerData.privacyConfig, encoding: .utf8),
              let userUnprotectedDomainsString = String(data: providerData.userUnprotectedDomains, encoding: .utf8),
              let userPreferencesString = String(data: providerData.userPreferences, encoding: .utf8) else {
            return nil
        }

        return  """
                 {
                    "success": {
                        "contentScope": \(privacyConfigJson),
                        "userUnprotectedDomains": \(userUnprotectedDomainsString),
                        "userPreferences": \(userPreferencesString)
                    }
                }
            """
    }

    private func buildReplacementsString() -> [String: String]? {
        var replacements: [String: String] = [:]
#if os(macOS)
        replacements["// INJECT isApp HERE"] = "isApp = true;"
#endif

        if #available(iOS 14, macOS 11, *) {
            replacements["// INJECT hasModernWebkitAPI HERE"] = "hasModernWebkitAPI = true;"

#if os(macOS)
            replacements["// INJECT supportsTopFrame HERE"] = "supportsTopFrame = true;"
#endif
        }

        guard let providerData = buildReplacementsData(),
              let privacyConfigJson = String(data: providerData.privacyConfig, encoding: .utf8),
              let userUnprotectedDomainsString = String(data: providerData.userUnprotectedDomains, encoding: .utf8),
              let userPreferencesString = String(data: providerData.userPreferences, encoding: .utf8) else {
            return nil
        }

        replacements["// INJECT contentScope HERE"] = "contentScope = " + privacyConfigJson + ";"
        replacements["// INJECT userUnprotectedDomains HERE"] = "userUnprotectedDomains = " + userUnprotectedDomainsString + ";"
        replacements["// INJECT userPreferences HERE"] = "userPreferences = " + userPreferencesString + ";"
        return replacements
    }

    private func buildReplacementsData() -> ProviderData? {
        guard let userUnprotectedDomains = try? JSONEncoder().encode(privacyConfigurationManager.privacyConfig.userUnprotectedDomains),
              let jsonProperties = try? JSONEncoder().encode(properties) else {
            return nil
        }
        return ProviderData(privacyConfig: privacyConfigurationManager.currentConfig,
                            userUnprotectedDomains: userUnprotectedDomains,
                            userPreferences: jsonProperties)
    }

    public class Builder {
        private var privacyConfigurationManager: PrivacyConfigurationManaging
        private var properties: ContentScopeProperties
        private var sourceStr: String = ""
        private var shouldLoadJS: Bool = false

        public init(privacyConfigurationManager: PrivacyConfigurationManaging, properties: ContentScopeProperties) {
            self.privacyConfigurationManager = privacyConfigurationManager
            self.properties = properties
        }

        public func build() -> DefaultAutofillSourceProvider {
            let provider = DefaultAutofillSourceProvider(privacyConfigurationManager: privacyConfigurationManager, properties: properties)

            if shouldLoadJS {
                provider.loadJS()
            }

            return provider
        }

        public func withJSLoading() -> Builder {
            self.shouldLoadJS = true
            return self
        }
    }
}
