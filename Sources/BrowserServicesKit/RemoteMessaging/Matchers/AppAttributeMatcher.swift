//
//  AppAttributeMatcher.swift
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

public enum AppFlavor: String {
    case flavorInternal = "internal"
    case flavorPublic = "public"
}

public struct AppAttributeMatcher: AttributeMatcher {

    private let bundleId: String
    private let appVersion: String
    private let flavor: AppFlavor
    private let statisticsStore: StatisticsStore
    private let variantManager: VariantManager

    public init(statisticsStore: StatisticsStore, variantManager: VariantManager, flavor: AppFlavor = .flavorPublic) {
        if let bundleId = Bundle.main.bundleIdentifier {
            self.init(bundleId: bundleId,
                      appVersion: AppVersion.shared.versionNumber,
                      flavor: flavor,
                      statisticsStore: statisticsStore,
                      variantManager: variantManager)
        } else {
            self.init(bundleId: "",
                      appVersion: AppVersion.shared.versionNumber,
                      flavor: flavor,
                      statisticsStore: statisticsStore,
                      variantManager: variantManager)
        }
    }

    public init(bundleId: String, appVersion: String, flavor: AppFlavor, statisticsStore: StatisticsStore, variantManager: VariantManager) {
        self.bundleId = bundleId
        self.appVersion = appVersion
        self.flavor = flavor
        self.statisticsStore = statisticsStore
        self.variantManager = variantManager
    }

    // swiftlint:disable cyclomatic_complexity
    func evaluate(matchingAttribute: MatchingAttribute) -> EvaluationResult? {
        switch matchingAttribute {
        case let matchingAttribute as FlavorMatchingAttribute:
            return StringArrayMatchingAttribute(matchingAttribute.value).matches(value: flavor.rawValue)
        case let matchingAttribute as AppIdMatchingAttribute:
            guard let value = matchingAttribute.value, !value.isEmpty else {
                return .fail
            }

            return StringMatchingAttribute(value).matches(value: bundleId)
        case let matchingAttribute as AppVersionMatchingAttribute:
            if matchingAttribute.value != MatchingAttributeDefaults.stringDefaultValue {
                return StringMatchingAttribute(matchingAttribute.value).matches(value: appVersion)
            } else {
                return RangeStringNumericMatchingAttribute(min: matchingAttribute.min, max: matchingAttribute.max).matches(value: appVersion)
            }
        case let matchingAttribute as AtbMatchingAttribute:
            guard let atb = statisticsStore.atb, let value = matchingAttribute.value else {
                return .fail
            }

            return StringMatchingAttribute(value).matches(value: atb)
        case let matchingAttribute as AppAtbMatchingAttribute:
            guard let atb = statisticsStore.appRetentionAtb, let value = matchingAttribute.value else {
                return .fail
            }

            return StringMatchingAttribute(value).matches(value: atb)
        case let matchingAttribute as SearchAtbMatchingAttribute:
            guard let atb = statisticsStore.searchRetentionAtb, let value = matchingAttribute.value else {
                return .fail
            }
            return StringMatchingAttribute(value).matches(value: atb)
        case let matchingAttribute as ExpVariantMatchingAttribute:
            guard let variant = variantManager.currentVariant?.name, let value = matchingAttribute.value else {
                return .fail
            }

            return StringMatchingAttribute(value).matches(value: variant)
        default:
            return nil
        }
    }
    // swiftlint:enable cyclomatic_complexity
}
