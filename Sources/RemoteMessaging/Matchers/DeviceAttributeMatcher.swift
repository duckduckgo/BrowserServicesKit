//
//  DeviceAttributeMatcher.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Common

public struct DeviceAttributeMatcher: AttributeMatcher {

    let osVersion: String
    let localeIdentifier: String

    public init() {
        self.init(osVersion: AppVersion.shared.osVersion, locale: Locale.current.identifier)
    }

    public init(osVersion: String, locale: String) {
        self.osVersion = osVersion
        self.localeIdentifier = locale
    }

    func evaluate(matchingAttribute: MatchingAttribute) -> EvaluationResult? {
        switch matchingAttribute {
        case let matchingAttribute as LocaleMatchingAttribute:
			return StringArrayMatchingAttribute(matchingAttribute.value).matches(value: LocaleMatchingAttribute.localeIdentifierAsJsonFormat(localeIdentifier))
        case let matchingAttribute as OSMatchingAttribute:
            if matchingAttribute.value != MatchingAttributeDefaults.stringDefaultValue {
				return StringMatchingAttribute(matchingAttribute.value).matches(value: osVersion)
            }
            return RangeStringNumericMatchingAttribute(min: matchingAttribute.min, max: matchingAttribute.max).matches(value: osVersion)
        default:
            return nil
        }
    }
}
