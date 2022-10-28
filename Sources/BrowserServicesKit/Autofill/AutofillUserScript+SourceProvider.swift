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
import Autofill

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
            replacements["// INJECT isApp HERE"] = "isApp = true;"
        #endif

        if #available(iOS 14, macOS 11, *) {
            replacements["// INJECT hasModernWebkitAPI HERE"] = "hasModernWebkitAPI = true;"
            
            #if os(macOS)
                replacements["// INJECT supportsTopFrame HERE"] = "supportsTopFrame = true;"
            #endif
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
        // TODO: use dynamic values
        let availableInputTypes = """
            {
                credentials: undefined,
                identities: {
                    firstName: true,
                    middleName: true,
                    lastName: true,
                    birthdayDay: true,
                    birthdayMonth: true,
                    birthdayYear: true,
                    addressStreet: true,
                    addressStreet2: true,
                    addressCity: true,
                    addressProvince: true,
                    addressPostalCode: true,
                    addressCountryCode: true,
                    phone: true,
                    emailAddress: true         // <- this is true if we have an address in identities OR if email protection is enabled
                },
                creditCards: {
                    cardName: true,
                    cardSecurityCode: true,
                    expirationMonth: true,
                    expirationYear: true,
                    cardNumber: true
                },
                email: true                    // <- this is specific for email protection
            }
        """
        replacements["// INJECT availableInputTypes HERE"] = "availableInputTypes = " + availableInputTypes + ";"

        // TODO: revert to "assets/autofill" once the integration is complete
        sourceStr = AutofillUserScript.loadJS("assets/autofill-debug", from: Autofill.bundle, withReplacements: replacements)
    }
}
