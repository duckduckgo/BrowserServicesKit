//
//  MatchingAttributes.swift
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

enum RuleAttributes {
    static let min = "min"
    static let max = "max"
    static let value = "value"
    static let fallback = "fallback"
    static let since = "since"
}

public protocol MatchingAttribute {
    var fallback: Bool? { get }
}

struct LocaleMatchingAttribute: SingleValueMatchingAttribute {
    var value: [String]? = []
    var fallback: Bool?

    static func localeIdentifierAsJsonFormat(_ localeIdentifier: String) -> String {
        let baseIdentifier = localeIdentifier.components(separatedBy: "@").first ?? localeIdentifier
        return baseIdentifier.replacingOccurrences(of: "_", with: "-")
    }
}

struct OSMatchingAttribute: StringRangeMatchingAttribute {
    static let defaultMaxValue: String = AppVersion.shared.osVersion

    var min: String = MatchingAttributeDefaults.stringDefaultValue
    var max: String = AppVersion.shared.osVersion
    var value: String = MatchingAttributeDefaults.stringDefaultValue
    var fallback: Bool?
}

struct IsInternalUserMatchingAttribute: SingleValueMatchingAttribute {
    var value: Bool?
    var fallback: Bool?
}

struct AppIdMatchingAttribute: SingleValueMatchingAttribute {
    var value: String?
    var fallback: Bool?
}

struct AppVersionMatchingAttribute: StringRangeMatchingAttribute {
    static let defaultMaxValue: String = AppVersion.shared.versionAndBuildNumber

    var min: String = MatchingAttributeDefaults.stringDefaultValue
    var max: String = AppVersion.shared.versionAndBuildNumber
    var value: String = MatchingAttributeDefaults.stringDefaultValue
    var fallback: Bool?
}

struct AtbMatchingAttribute: SingleValueMatchingAttribute {
    var value: String?
    var fallback: Bool?
}

struct AppAtbMatchingAttribute: SingleValueMatchingAttribute {
    var value: String?
    var fallback: Bool?
}

struct SearchAtbMatchingAttribute: SingleValueMatchingAttribute {
    var value: String?
    var fallback: Bool?
}

struct ExpVariantMatchingAttribute: SingleValueMatchingAttribute {
    var value: String?
    var fallback: Bool?
}

struct EmailEnabledMatchingAttribute: SingleValueMatchingAttribute {
    var value: Bool?
    var fallback: Bool?
}

struct WidgetAddedMatchingAttribute: SingleValueMatchingAttribute {
    var value: Bool?
    var fallback: Bool?
}

struct BookmarksMatchingAttribute: NumericRangeMatchingAttribute {
    var min: Int = MatchingAttributeDefaults.intDefaultValue
    var max: Int = MatchingAttributeDefaults.intDefaultMaxValue
    var value: Int = MatchingAttributeDefaults.intDefaultValue
    var fallback: Bool?
}

struct FavoritesMatchingAttribute: NumericRangeMatchingAttribute {
    var min: Int = MatchingAttributeDefaults.intDefaultValue
    var max: Int = MatchingAttributeDefaults.intDefaultMaxValue
    var value: Int = MatchingAttributeDefaults.intDefaultValue
    var fallback: Bool?
}

struct AppThemeMatchingAttribute: SingleValueMatchingAttribute {
    var value: String?
    var fallback: Bool?
}

struct DaysSinceInstalledMatchingAttribute: NumericRangeMatchingAttribute {
    var min: Int = MatchingAttributeDefaults.intDefaultValue
    var max: Int = MatchingAttributeDefaults.intDefaultMaxValue
    var value: Int = MatchingAttributeDefaults.intDefaultValue
    var fallback: Bool?
}

struct DaysSinceNetPEnabledMatchingAttribute: NumericRangeMatchingAttribute {
    var min: Int = MatchingAttributeDefaults.intDefaultValue
    var max: Int = MatchingAttributeDefaults.intDefaultMaxValue
    var value: Int = MatchingAttributeDefaults.intDefaultValue
    var fallback: Bool?
}

struct IsPrivacyProEligibleUserMatchingAttribute: SingleValueMatchingAttribute {
    var value: Bool?
    var fallback: Bool?
}

struct IsPrivacyProSubscriberUserMatchingAttribute: SingleValueMatchingAttribute {
    var value: Bool?
    var fallback: Bool?
}

struct PrivacyProDaysSinceSubscribedMatchingAttribute: NumericRangeMatchingAttribute {
    var min: Int = MatchingAttributeDefaults.intDefaultValue
    var max: Int = MatchingAttributeDefaults.intDefaultMaxValue
    var value: Int = MatchingAttributeDefaults.intDefaultValue
    var fallback: Bool?
}

struct PrivacyProDaysUntilExpiryMatchingAttribute: NumericRangeMatchingAttribute {
    var min: Int = MatchingAttributeDefaults.intDefaultValue
    var max: Int = MatchingAttributeDefaults.intDefaultMaxValue
    var value: Int = MatchingAttributeDefaults.intDefaultValue
    var fallback: Bool?
}

struct PrivacyProPurchasePlatformMatchingAttribute: SingleValueMatchingAttribute {
    var value: [String]? = []
    var fallback: Bool?
}

struct PrivacyProSubscriptionStatusMatchingAttribute: SingleValueMatchingAttribute {
    var value: [String]? = []
    var fallback: Bool?
}

struct InteractedWithMessageMatchingAttribute: SingleValueMatchingAttribute {
    var value: [String]? = []
    var fallback: Bool?
}

struct IsInstalledMacAppStoreMatchingAttribute: SingleValueMatchingAttribute {
    var value: Bool?
    var fallback: Bool?
}

struct UnknownMatchingAttribute: MatchingAttribute, Equatable {
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else { return }

        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(fallback: Bool?) {
        self.fallback = fallback
    }
}

enum MatchingAttributeDefaults {
    static let intDefaultValue = -1
    static let intDefaultMaxValue = Int.max
    static let stringDefaultValue = ""
}

// MARK: -

struct BooleanMatchingAttribute: Equatable {
    var value: Bool

    init(_ value: Bool) {
        self.value = value
    }

    func matches(value: Bool) -> EvaluationResult {
        return EvaluationResultModel.result(value: self.value == value)
    }
}

struct IntMatchingAttribute: Equatable {
    var value: Int

    init(_ value: Int) {
        self.value = value
    }

    func matches(value: Int) -> EvaluationResult {
        return EvaluationResultModel.result(value: self.value == value)
    }
}

struct RangeIntMatchingAttribute: Equatable {
    var min: Int
    var max: Int

    func matches(value: Int) -> EvaluationResult {
        return EvaluationResultModel.result(value: (value >= self.min) && (value <= self.max))
    }
}

struct StringMatchingAttribute: Equatable {
    var value: String

    init(_ value: String) {
        self.value = value.lowercased()
    }

    func matches(value: String) -> EvaluationResult {
        return EvaluationResultModel.result(value: self.value == value.lowercased())
    }
}

struct StringArrayMatchingAttribute: Equatable {
    var values: [String]

    init(_ values: [String]?) {
        self.values = (values ?? []).map { $0.lowercased() }
    }

    func matches(value: String) -> EvaluationResult {
        return EvaluationResultModel.result(value: values.contains(value.lowercased()))
    }
}

struct RangeStringNumericMatchingAttribute: Equatable {
    var min: String
    var max: String

    func matches(value: String) -> EvaluationResult {
        if !value.matches(pattern: "[0-9]+(\\.[0-9]+)*") {
            return .fail
        }

        let paddedMin = padWithZeros(version: min, toMatch: value)
        let paddedMax = padWithZeros(version: max, toMatch: value)
        let paddedValue = padWithZeros(version: value, toMatch: max)

        if paddedMin.compare(paddedValue, options: .numeric) == .orderedDescending { return .fail }
        if paddedMax.compare(paddedValue, options: .numeric) == .orderedAscending { return .fail }

        return .match
    }

    private func padWithZeros(version: String, toMatch: String) -> String {
        let versionComponents = version.split(separator: ".").map(String.init)
        let matchComponents = toMatch.split(separator: ".").map(String.init)

        if versionComponents.count >= matchComponents.count {
            return version
        }

        return version + String(repeating: ".0", count: matchComponents.count - versionComponents.count)
    }
}
