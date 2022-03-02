//
//  AutofillUserScript+SourceProvider.swift
//  DuckDuckGo
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

public protocol AutofillUserScriptSourceProvider {
    var source: String { get }
}

public class DefaultAutofillSourceProvider: AutofillUserScriptSourceProvider {
    
    private var sourceStr: String
    
    public var source: String {
        return sourceStr
    }
    
    public init(privacyConfigurationManager: PrivacyConfigurationManager, properties: ContentScopeProperties) {
        var replacements: [String: String] = [:]
        #if os(macOS)
            replacements["// INJECT supportsTopFrame HERE"] = "supportsTopFrame = true;"
            replacements["// INJECT isApp HERE"] = "isApp = true;"
        #endif

        if #available(iOS 14, macOS 11, *) {
            replacements["// INJECT hasModernWebkitAPI HERE"] = "hasModernWebkitAPI = true;"
        }
        
        guard let privacyConfigJson = String(data: privacyConfigurationManager.currentConfig, encoding: .utf8),
              let userUnprotectedDomains = try? JSONEncoder().encode(privacyConfigurationManager.privacyConfig.userUnprotectedDomains),
              let userUnprotectedDomainsString = String(data: userUnprotectedDomains, encoding: .utf8),
              let jsonProperties = try? JSONEncoder().encode(properties),
              let jsonPropertiesString = String(data: jsonProperties, encoding: .utf8)
              else {
            sourceStr = ""
            return
        }
        replacements["// INJECT contentScope HERE"] = "contentScope = " + privacyConfigJson + ";"
        replacements["// INJECT userUnprotectedDomains HERE"] = "userUnprotectedDomains = " + userUnprotectedDomainsString + ";"
        replacements["// INJECT userPreferences HERE"] = "userPreferences = " + jsonPropertiesString + ";"

        sourceStr = AutofillUserScript.loadJS("autofill", from: Bundle.module, withReplacements: replacements)
    }
}
