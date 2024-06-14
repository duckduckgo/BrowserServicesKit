//
//  UserAttributeMatcher.swift
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

public struct UserAttributeMatcher: AttributeMatcher {

    private enum PrivacyProSubscriptionStatus: String {
        case active
        case expiring
        case expired
    }

    private let statisticsStore: StatisticsStore
    private let variantManager: VariantManager
    private let emailManager: EmailManager
    private let appTheme: String
    private let bookmarksCount: Int
    private let favoritesCount: Int
    private let isWidgetInstalled: Bool
    private let daysSinceNetPEnabled: Int
    private let isPrivacyProEligibleUser: Bool
    private let isPrivacyProSubscriber: Bool
    private let privacyProDaysSinceSubscribed: Int
    private let privacyProDaysUntilExpiry: Int
    private let privacyProPurchasePlatform: String?
    private let isPrivacyProSubscriptionActive: Bool
    private let isPrivacyProSubscriptionExpiring: Bool
    private let isPrivacyProSubscriptionExpired: Bool

    public init(statisticsStore: StatisticsStore,
                variantManager: VariantManager,
                emailManager: EmailManager = EmailManager(),
                bookmarksCount: Int,
                favoritesCount: Int,
                appTheme: String,
                isWidgetInstalled: Bool,
                daysSinceNetPEnabled: Int,
                isPrivacyProEligibleUser: Bool,
                isPrivacyProSubscriber: Bool,
                privacyProDaysSinceSubscribed: Int,
                privacyProDaysUntilExpiry: Int,
                privacyProPurchasePlatform: String?,
                isPrivacyProSubscriptionActive: Bool,
                isPrivacyProSubscriptionExpiring: Bool,
                isPrivacyProSubscriptionExpired: Bool
	) {
        self.statisticsStore = statisticsStore
        self.variantManager = variantManager
		self.emailManager = emailManager
        self.appTheme = appTheme
        self.bookmarksCount = bookmarksCount
        self.favoritesCount = favoritesCount
        self.isWidgetInstalled = isWidgetInstalled
        self.daysSinceNetPEnabled = daysSinceNetPEnabled
        self.isPrivacyProEligibleUser = isPrivacyProEligibleUser
        self.isPrivacyProSubscriber = isPrivacyProSubscriber
        self.privacyProDaysSinceSubscribed = privacyProDaysSinceSubscribed
        self.privacyProDaysUntilExpiry = privacyProDaysUntilExpiry
        self.privacyProPurchasePlatform = privacyProPurchasePlatform
        self.isPrivacyProSubscriptionActive = isPrivacyProSubscriptionActive
        self.isPrivacyProSubscriptionExpiring = isPrivacyProSubscriptionExpiring
        self.isPrivacyProSubscriptionExpired = isPrivacyProSubscriptionExpired
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func evaluate(matchingAttribute: MatchingAttribute) -> EvaluationResult? {
        switch matchingAttribute {
        case let matchingAttribute as AppThemeMatchingAttribute:
            guard let value = matchingAttribute.value else {
                return .fail
            }

            return StringMatchingAttribute(value).matches(value: appTheme)
        case let matchingAttribute as BookmarksMatchingAttribute:
            if matchingAttribute.value != MatchingAttributeDefaults.intDefaultValue {
                return IntMatchingAttribute(matchingAttribute.value).matches(value: bookmarksCount)
            } else {
                return RangeIntMatchingAttribute(min: matchingAttribute.min, max: matchingAttribute.max).matches(value: bookmarksCount)
            }
        case let matchingAttribute as DaysSinceInstalledMatchingAttribute:
            guard let installDate = statisticsStore.installDate,
                  let daysSinceInstall = Calendar.current.numberOfDaysBetween(installDate, and: Date()) else {
                return .fail
            }

            if matchingAttribute.value != MatchingAttributeDefaults.intDefaultValue {
                return IntMatchingAttribute(matchingAttribute.value).matches(value: daysSinceInstall)
            } else {
                return RangeIntMatchingAttribute(min: matchingAttribute.min, max: matchingAttribute.max).matches(value: daysSinceInstall)
            }
        case let matchingAttribute as EmailEnabledMatchingAttribute:
            guard let value = matchingAttribute.value else {
                return .fail
            }

            return BooleanMatchingAttribute(value).matches(value: emailManager.isSignedIn)
        case let matchingAttribute as FavoritesMatchingAttribute:
            if matchingAttribute.value != MatchingAttributeDefaults.intDefaultValue {
                return IntMatchingAttribute(matchingAttribute.value).matches(value: favoritesCount)
            } else {
                return RangeIntMatchingAttribute(min: matchingAttribute.min, max: matchingAttribute.max).matches(value: favoritesCount)
            }
        case let matchingAttribute as WidgetAddedMatchingAttribute:
            guard let value = matchingAttribute.value else {
                return .fail
            }

            return BooleanMatchingAttribute(value).matches(value: isWidgetInstalled)
        case let matchingAttribute as DaysSinceNetPEnabledMatchingAttribute:
            if matchingAttribute.value != MatchingAttributeDefaults.intDefaultValue {
                return IntMatchingAttribute(matchingAttribute.value).matches(value: daysSinceNetPEnabled)
            } else {
                return RangeIntMatchingAttribute(min: matchingAttribute.min, max: matchingAttribute.max).matches(value: daysSinceNetPEnabled)
            }
        case let matchingAttribute as IsPrivacyProEligibleUserMatchingAttribute:
            guard let value = matchingAttribute.value else {
                return .fail
            }

            return BooleanMatchingAttribute(value).matches(value: isPrivacyProEligibleUser)
        case let matchingAttribute as IsPrivacyProSubscriberUserMatchingAttribute:
            guard let value = matchingAttribute.value else {
                return .fail
            }

            return BooleanMatchingAttribute(value).matches(value: isPrivacyProSubscriber)
        case let matchingAttribute as PrivacyProDaysSinceSubscribedMatchingAttribute:
            if matchingAttribute.value != MatchingAttributeDefaults.intDefaultValue {
                return IntMatchingAttribute(matchingAttribute.value).matches(value: privacyProDaysSinceSubscribed)
            } else {
                return RangeIntMatchingAttribute(min: matchingAttribute.min, max: matchingAttribute.max).matches(value: privacyProDaysSinceSubscribed)
            }
        case let matchingAttribute as PrivacyProDaysUntilExpiryMatchingAttribute:
            if matchingAttribute.value != MatchingAttributeDefaults.intDefaultValue {
                return IntMatchingAttribute(matchingAttribute.value).matches(value: privacyProDaysUntilExpiry)
            } else {
                return RangeIntMatchingAttribute(min: matchingAttribute.min, max: matchingAttribute.max).matches(value: privacyProDaysUntilExpiry)
            }
        case let matchingAttribute as PrivacyProPurchasePlatformMatchingAttribute:
            return StringArrayMatchingAttribute(matchingAttribute.value).matches(value: privacyProPurchasePlatform ?? "")
        case let matchingAttribute as PrivacyProSubscriptionStatusMatchingAttribute:
            guard let value = matchingAttribute.value else {
                return .fail
            }

            guard let status = PrivacyProSubscriptionStatus(rawValue: value) else {
                return .fail
            }

            switch status {
            case .active: return isPrivacyProSubscriptionActive ? .match : .fail
            case .expiring: return isPrivacyProSubscriptionExpiring ? .match : .fail
            case .expired: return isPrivacyProSubscriptionExpired ? .match : .fail
            }
        default:
            assertionFailure("Could not find matching attribute")
            return nil
        }
    }

}
