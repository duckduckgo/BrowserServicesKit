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

private enum RuleAttributes {
    static let min = "min"
    static let max = "max"
    static let value = "value"
    static let fallback = "fallback"
    static let since = "since"
}

protocol MatchingAttribute {
    var fallback: Bool? { get }
}

struct LocaleMatchingAttribute: MatchingAttribute, Equatable {
    var value: [String] = []
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else {
            return
        }
        if let value = jsonMatchingAttribute[RuleAttributes.value] as? [String] {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(value: [String], fallback: Bool?) {
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: LocaleMatchingAttribute, rhs: LocaleMatchingAttribute) -> Bool {
        return lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }

    static func localeIdentifierAsJsonFormat(_ localeIdentifier: String) -> String {
        return localeIdentifier.replacingOccurrences(of: "_", with: "-")
    }
}

struct OSMatchingAttribute: MatchingAttribute, Equatable {
    var min: String = MatchingAttributeDefaults.stringDefaultValue
    var max: String = AppVersion.shared.osVersion
    var value: String = MatchingAttributeDefaults.stringDefaultValue
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else { return }

        if let min = jsonMatchingAttribute[RuleAttributes.min] as? String {
            self.min = min
        }
        if let max = jsonMatchingAttribute[RuleAttributes.max] as? String {
            self.max = max
        }
        if let value = jsonMatchingAttribute[RuleAttributes.value] as? String {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(min: String = MatchingAttributeDefaults.stringDefaultValue,
         max: String = AppVersion.shared.osVersion,
         value: String = MatchingAttributeDefaults.stringDefaultValue,
         fallback: Bool?) {
        self.min = min
        self.max = max
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: OSMatchingAttribute, rhs: OSMatchingAttribute) -> Bool {
        return lhs.min == rhs.min && lhs.max == rhs.max && lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }
}

struct IsInternalUserMatchingAttribute: MatchingAttribute, Equatable {
    var value: Bool?
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else { return }

        if let value = jsonMatchingAttribute[RuleAttributes.value] as? Bool {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(value: Bool?, fallback: Bool?) {
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: IsInternalUserMatchingAttribute, rhs: IsInternalUserMatchingAttribute) -> Bool {
        return lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }
}

struct AppIdMatchingAttribute: MatchingAttribute, Equatable {
    var value: String?
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else { return }

        if let value = jsonMatchingAttribute[RuleAttributes.value] as? String {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(value: String?, fallback: Bool?) {
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: AppIdMatchingAttribute, rhs: AppIdMatchingAttribute) -> Bool {
        return lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }
}

struct AppVersionMatchingAttribute: MatchingAttribute, Equatable {
    var min: String = MatchingAttributeDefaults.stringDefaultValue
    var max: String = AppVersion.shared.versionAndBuildNumber
    var value: String = MatchingAttributeDefaults.stringDefaultValue
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else { return }

        if let min = jsonMatchingAttribute[RuleAttributes.min] as? String {
            self.min = min
        }
        if let max = jsonMatchingAttribute[RuleAttributes.max] as? String {
            self.max = max
        }
        if let value = jsonMatchingAttribute[RuleAttributes.value] as? String {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(min: String = MatchingAttributeDefaults.stringDefaultValue,
         max: String = AppVersion.shared.versionAndBuildNumber,
         value: String = MatchingAttributeDefaults.stringDefaultValue,
         fallback: Bool?) {
        self.min = min
        self.max = max
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: AppVersionMatchingAttribute, rhs: AppVersionMatchingAttribute) -> Bool {
        return lhs.min == rhs.min && lhs.max == rhs.max && lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }
}

struct AtbMatchingAttribute: MatchingAttribute, Equatable {
    var value: String?
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else { return }

        if let value = jsonMatchingAttribute[RuleAttributes.value] as? String {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(value: String?, fallback: Bool?) {
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: AtbMatchingAttribute, rhs: AtbMatchingAttribute) -> Bool {
        return lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }
}

struct AppAtbMatchingAttribute: MatchingAttribute, Equatable {
    var value: String?
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else { return }

        if let value = jsonMatchingAttribute[RuleAttributes.value] as? String {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(value: String?, fallback: Bool?) {
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: AppAtbMatchingAttribute, rhs: AppAtbMatchingAttribute) -> Bool {
        return lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }
}

struct SearchAtbMatchingAttribute: MatchingAttribute, Equatable {
    var value: String?
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else { return }

        if let value = jsonMatchingAttribute[RuleAttributes.value] as? String {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(value: String?, fallback: Bool?) {
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: SearchAtbMatchingAttribute, rhs: SearchAtbMatchingAttribute) -> Bool {
        return lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }
}

struct ExpVariantMatchingAttribute: MatchingAttribute, Equatable {
    var value: String?
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else { return }

        if let value = jsonMatchingAttribute[RuleAttributes.value] as? String {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(value: String?, fallback: Bool?) {
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: ExpVariantMatchingAttribute, rhs: ExpVariantMatchingAttribute) -> Bool {
        return lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }
}

struct EmailEnabledMatchingAttribute: MatchingAttribute, Equatable {
    var value: Bool?
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else { return }

        if let value = jsonMatchingAttribute[RuleAttributes.value] as? Bool {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(value: Bool?, fallback: Bool?) {
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: EmailEnabledMatchingAttribute, rhs: EmailEnabledMatchingAttribute) -> Bool {
        return lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }
}

struct WidgetAddedMatchingAttribute: MatchingAttribute, Equatable {
    var value: Bool?
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else { return }

        if let value = jsonMatchingAttribute[RuleAttributes.value] as? Bool {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(value: Bool?, fallback: Bool?) {
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: WidgetAddedMatchingAttribute, rhs: WidgetAddedMatchingAttribute) -> Bool {
        return lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }
}

struct BookmarksMatchingAttribute: MatchingAttribute, Equatable {
    var min: Int = MatchingAttributeDefaults.intDefaultValue
    var max: Int = MatchingAttributeDefaults.intDefaultMaxValue
    var value: Int = MatchingAttributeDefaults.intDefaultValue
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else { return }

        if let min = jsonMatchingAttribute[RuleAttributes.min] as? Int {
            self.min = min
        }
        if let max = jsonMatchingAttribute[RuleAttributes.max] as? Int {
            self.max = max
        }
        if let value = jsonMatchingAttribute[RuleAttributes.value] as? Int {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(min: Int = MatchingAttributeDefaults.intDefaultValue,
         max: Int = MatchingAttributeDefaults.intDefaultMaxValue,
         value: Int = MatchingAttributeDefaults.intDefaultValue,
         fallback: Bool?) {
        self.min = min
        self.max = max
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: BookmarksMatchingAttribute, rhs: BookmarksMatchingAttribute) -> Bool {
        return lhs.min == rhs.min && lhs.max == rhs.max && lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }
}

struct FavoritesMatchingAttribute: MatchingAttribute, Equatable {
    var min: Int = MatchingAttributeDefaults.intDefaultValue
    var max: Int = MatchingAttributeDefaults.intDefaultMaxValue
    var value: Int = MatchingAttributeDefaults.intDefaultValue
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else { return }

        if let min = jsonMatchingAttribute[RuleAttributes.min] as? Int {
            self.min = min
        }
        if let max = jsonMatchingAttribute[RuleAttributes.max] as? Int {
            self.max = max
        }
        if let value = jsonMatchingAttribute[RuleAttributes.value] as? Int {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(min: Int = MatchingAttributeDefaults.intDefaultValue,
         max: Int = MatchingAttributeDefaults.intDefaultMaxValue,
         value: Int = MatchingAttributeDefaults.intDefaultValue,
         fallback: Bool?) {
        self.min = min
        self.max = max
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: FavoritesMatchingAttribute, rhs: FavoritesMatchingAttribute) -> Bool {
        return lhs.min == rhs.min && lhs.max == rhs.max && lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }
}

struct AppThemeMatchingAttribute: MatchingAttribute, Equatable {
    var value: String?
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else { return }

        if let value = jsonMatchingAttribute[RuleAttributes.value] as? String {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(value: String?, fallback: Bool?) {
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: AppThemeMatchingAttribute, rhs: AppThemeMatchingAttribute) -> Bool {
        return lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }
}

struct DaysSinceInstalledMatchingAttribute: MatchingAttribute, Equatable {
    var min: Int = MatchingAttributeDefaults.intDefaultValue
    var max: Int = MatchingAttributeDefaults.intDefaultMaxValue
    var value: Int = MatchingAttributeDefaults.intDefaultValue
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else { return }

        if let min = jsonMatchingAttribute[RuleAttributes.min] as? Int {
            self.min = min
        }
        if let max = jsonMatchingAttribute[RuleAttributes.max] as? Int {
            self.max = max
        }
        if let value = jsonMatchingAttribute[RuleAttributes.value] as? Int {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(min: Int = MatchingAttributeDefaults.intDefaultValue,
         max: Int = MatchingAttributeDefaults.intDefaultMaxValue,
         value: Int = MatchingAttributeDefaults.intDefaultValue,
         fallback: Bool?) {
        self.min = min
        self.max = max
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: DaysSinceInstalledMatchingAttribute, rhs: DaysSinceInstalledMatchingAttribute) -> Bool {
        return lhs.min == rhs.min && lhs.max == rhs.max && lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }
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

    static func == (lhs: UnknownMatchingAttribute, rhs: UnknownMatchingAttribute) -> Bool {
        return lhs.fallback == rhs.fallback
    }
}

struct BooleanMatchingAttribute: Equatable {
    var value: Bool

    init(_ value: Bool) {
        self.value = value
    }

    func matches(value: Bool) -> EvaluationResult {
        return EvaluationResultModel.result(value: self.value == value)
    }

    static func == (lhs: BooleanMatchingAttribute, rhs: BooleanMatchingAttribute) -> Bool {
        return lhs.value == rhs.value
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

    static func == (lhs: IntMatchingAttribute, rhs: IntMatchingAttribute) -> Bool {
        return lhs.value == rhs.value
    }
}

struct RangeIntMatchingAttribute: Equatable {
    var min: Int
    var max: Int

    func matches(value: Int) -> EvaluationResult {
        return EvaluationResultModel.result(value: (value >= self.min) && (value <= self.max))
    }

    static func == (lhs: RangeIntMatchingAttribute, rhs: RangeIntMatchingAttribute) -> Bool {
        return lhs.min == rhs.min && lhs.max == rhs.max
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

    static func == (lhs: StringMatchingAttribute, rhs: StringMatchingAttribute) -> Bool {
        return lhs.value == rhs.value
    }
}

struct StringArrayMatchingAttribute: Equatable {
    var values: [String]

    init(_ values: [String]) {
        self.values = values.map { $0.lowercased() }
    }

    func matches(value: String) -> EvaluationResult {
        return EvaluationResultModel.result(value: values.contains(value.lowercased()))
    }

    static func == (lhs: StringArrayMatchingAttribute, rhs: StringArrayMatchingAttribute) -> Bool {
        return lhs.values == rhs.values
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

    static func == (lhs: RangeStringNumericMatchingAttribute, rhs: RangeStringNumericMatchingAttribute) -> Bool {
        return lhs.min == rhs.min && lhs.max == rhs.max
    }
}

struct DaysSinceNetPEnabledMatchingAttribute: MatchingAttribute, Equatable {
    var min: Int = MatchingAttributeDefaults.intDefaultValue
    var max: Int = MatchingAttributeDefaults.intDefaultMaxValue
    var value: Int = MatchingAttributeDefaults.intDefaultValue
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else { return }

        if let min = jsonMatchingAttribute[RuleAttributes.min] as? Int {
            self.min = min
        }
        if let max = jsonMatchingAttribute[RuleAttributes.max] as? Int {
            self.max = max
        }
        if let value = jsonMatchingAttribute[RuleAttributes.value] as? Int {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(min: Int = MatchingAttributeDefaults.intDefaultValue,
         max: Int = MatchingAttributeDefaults.intDefaultMaxValue,
         value: Int = MatchingAttributeDefaults.intDefaultValue,
         fallback: Bool?) {
        self.min = min
        self.max = max
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: DaysSinceNetPEnabledMatchingAttribute, rhs: DaysSinceNetPEnabledMatchingAttribute) -> Bool {
        return lhs.min == rhs.min && lhs.max == rhs.max && lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }
}

struct IsPrivacyProEligibleUserMatchingAttribute: MatchingAttribute, Equatable {
    var value: Bool?
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else { return }

        if let value = jsonMatchingAttribute[RuleAttributes.value] as? Bool {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(value: Bool?, fallback: Bool?) {
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: IsPrivacyProEligibleUserMatchingAttribute, rhs: IsPrivacyProEligibleUserMatchingAttribute) -> Bool {
        return lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }
}

struct IsPrivacyProSubscriberUserMatchingAttribute: MatchingAttribute, Equatable {
    var value: Bool?
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else { return }

        if let value = jsonMatchingAttribute[RuleAttributes.value] as? Bool {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(value: Bool?, fallback: Bool?) {
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: IsPrivacyProSubscriberUserMatchingAttribute, rhs: IsPrivacyProSubscriberUserMatchingAttribute) -> Bool {
        return lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }
}

struct PrivacyProDaysSinceSubscribedMatchingAttribute: MatchingAttribute, Equatable {
    var min: Int = MatchingAttributeDefaults.intDefaultValue
    var max: Int = MatchingAttributeDefaults.intDefaultMaxValue
    var value: Int = MatchingAttributeDefaults.intDefaultValue
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else { return }

        if let min = jsonMatchingAttribute[RuleAttributes.min] as? Int {
            self.min = min
        }
        if let max = jsonMatchingAttribute[RuleAttributes.max] as? Int {
            self.max = max
        }
        if let value = jsonMatchingAttribute[RuleAttributes.value] as? Int {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(min: Int = MatchingAttributeDefaults.intDefaultValue,
         max: Int = MatchingAttributeDefaults.intDefaultMaxValue,
         value: Int = MatchingAttributeDefaults.intDefaultValue,
         fallback: Bool?) {
        self.min = min
        self.max = max
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: PrivacyProDaysSinceSubscribedMatchingAttribute, rhs: PrivacyProDaysSinceSubscribedMatchingAttribute) -> Bool {
        return lhs.min == rhs.min && lhs.max == rhs.max && lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }
}

struct PrivacyProDaysUntilExpiryMatchingAttribute: MatchingAttribute, Equatable {
    var min: Int = MatchingAttributeDefaults.intDefaultValue
    var max: Int = MatchingAttributeDefaults.intDefaultMaxValue
    var value: Int = MatchingAttributeDefaults.intDefaultValue
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else { return }

        if let min = jsonMatchingAttribute[RuleAttributes.min] as? Int {
            self.min = min
        }
        if let max = jsonMatchingAttribute[RuleAttributes.max] as? Int {
            self.max = max
        }
        if let value = jsonMatchingAttribute[RuleAttributes.value] as? Int {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(min: Int = MatchingAttributeDefaults.intDefaultValue,
         max: Int = MatchingAttributeDefaults.intDefaultMaxValue,
         value: Int = MatchingAttributeDefaults.intDefaultValue,
         fallback: Bool?) {
        self.min = min
        self.max = max
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: PrivacyProDaysUntilExpiryMatchingAttribute, rhs: PrivacyProDaysUntilExpiryMatchingAttribute) -> Bool {
        return lhs.min == rhs.min && lhs.max == rhs.max && lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }
}

struct PrivacyProPurchasePlatformMatchingAttribute: MatchingAttribute, Equatable {
    var value: [String] = []
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else {
            return
        }
        if let value = jsonMatchingAttribute[RuleAttributes.value] as? [String] {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(value: [String], fallback: Bool?) {
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: PrivacyProPurchasePlatformMatchingAttribute, rhs: PrivacyProPurchasePlatformMatchingAttribute) -> Bool {
        return lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }
}

struct PrivacyProSubscriptionStatusMatchingAttribute: MatchingAttribute, Equatable {
    var value: String?
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else { return }

        if let value = jsonMatchingAttribute[RuleAttributes.value] as? String {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(value: String?, fallback: Bool?) {
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: PrivacyProSubscriptionStatusMatchingAttribute, rhs: PrivacyProSubscriptionStatusMatchingAttribute) -> Bool {
        return lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }
}

struct InteractedWithMessageMatchingAttribute: MatchingAttribute, Equatable {
    var value: [String] = []
    var fallback: Bool?

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else {
            return
        }
        if let value = jsonMatchingAttribute[RuleAttributes.value] as? [String] {
            self.value = value
        }
        if let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool {
            self.fallback = fallback
        }
    }

    init(value: [String], fallback: Bool?) {
        self.value = value
        self.fallback = fallback
    }

    static func == (lhs: InteractedWithMessageMatchingAttribute, rhs: InteractedWithMessageMatchingAttribute) -> Bool {
        return lhs.value == rhs.value && lhs.fallback == rhs.fallback
    }
}

enum MatchingAttributeDefaults {
    static let intDefaultValue = -1
    static let intDefaultMaxValue = Int.max
    static let stringDefaultValue = ""
}
