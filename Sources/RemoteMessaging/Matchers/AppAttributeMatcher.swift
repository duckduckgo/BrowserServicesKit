//
//  AppAttributeMatcher.swift
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
import BrowserServicesKit

#if os(iOS)
public typealias AppAttributeMatcher = MobileAppAttributeMatcher
#elseif os(macOS)
public typealias AppAttributeMatcher = DesktopAppAttributeMatcher
#endif

public typealias MobileAppAttributeMatcher = CommonAppAttributeMatcher

public struct DesktopAppAttributeMatcher: AttributeMatching {
    private let isInstalledMacAppStore: Bool

    private let commonAppAttributeMatcher: CommonAppAttributeMatcher

    public init(statisticsStore: StatisticsStore, variantManager: VariantManager, isInternalUser: Bool = true, isInstalledMacAppStore: Bool) {
        self.isInstalledMacAppStore = isInstalledMacAppStore

        commonAppAttributeMatcher = .init(statisticsStore: statisticsStore, variantManager: variantManager, isInternalUser: isInternalUser)
    }

    public init(
        bundleId: String,
        appVersion: String,
        isInternalUser: Bool,
        statisticsStore: StatisticsStore,
        variantManager: VariantManager,
        isInstalledMacAppStore: Bool
    ) {
        self.isInstalledMacAppStore = isInternalUser

        commonAppAttributeMatcher = .init(
            bundleId: bundleId,
            appVersion: appVersion,
            isInternalUser: isInternalUser,
            statisticsStore: statisticsStore,
            variantManager: variantManager
        )
    }

    public func evaluate(matchingAttribute: MatchingAttribute) -> EvaluationResult? {
        switch matchingAttribute {
        case let matchingAttribute as IsInstalledMacAppStoreMatchingAttribute:
            guard let value = matchingAttribute.value else {
                return .fail
            }

            return BooleanMatchingAttribute(value).matches(value: isInstalledMacAppStore)
        default:
            return commonAppAttributeMatcher.evaluate(matchingAttribute: matchingAttribute)
        }
    }
}

public struct CommonAppAttributeMatcher: AttributeMatching {

    private let bundleId: String
    private let appVersion: String
    private let isInternalUser: Bool
    private let statisticsStore: StatisticsStore
    private let variantManager: VariantManager

    public init(statisticsStore: StatisticsStore, variantManager: VariantManager, isInternalUser: Bool = true) {
        if AppVersion.shared.identifier.isEmpty {
            assertionFailure("BundleIdentifier should not be empty")
        }
        self.init(bundleId: AppVersion.shared.identifier,
                  appVersion: AppVersion.shared.versionAndBuildNumber,
                  isInternalUser: isInternalUser,
                  statisticsStore: statisticsStore,
                  variantManager: variantManager)
    }

    public init(bundleId: String, appVersion: String, isInternalUser: Bool, statisticsStore: StatisticsStore, variantManager: VariantManager) {
        self.bundleId = bundleId
        self.appVersion = appVersion
        self.isInternalUser = isInternalUser
        self.statisticsStore = statisticsStore
        self.variantManager = variantManager
    }

    public func evaluate(matchingAttribute: MatchingAttribute) -> EvaluationResult? {
        switch matchingAttribute {
        case let matchingAttribute as IsInternalUserMatchingAttribute:
            guard let value = matchingAttribute.value else {
                return .fail
            }

            return BooleanMatchingAttribute(value).matches(value: isInternalUser)
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
}
