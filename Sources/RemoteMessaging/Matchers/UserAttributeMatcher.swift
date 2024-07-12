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

#if os(iOS)
public typealias UserAttributeMatcher = MobileUserAttributeMatcher
#elseif os(macOS)
public typealias UserAttributeMatcher = DesktopUserAttributeMatcher
#endif

public struct MobileUserAttributeMatcher: AttributeMatching {

    private enum PrivacyProSubscriptionStatus: String {
        case active
        case expiring
        case expired
    }

    private let isWidgetInstalled: Bool

    private let commonUserAttributeMatcher: CommonUserAttributeMatcher

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
                isPrivacyProSubscriptionExpired: Bool,
                dismissedMessageIds: [String]
    ) {
        self.isWidgetInstalled = isWidgetInstalled

        commonUserAttributeMatcher = .init(
            statisticsStore: statisticsStore,
            variantManager: variantManager,
            emailManager: emailManager,
            bookmarksCount: bookmarksCount,
            favoritesCount: favoritesCount,
            appTheme: appTheme,
            daysSinceNetPEnabled: daysSinceNetPEnabled,
            isPrivacyProEligibleUser: isPrivacyProEligibleUser,
            isPrivacyProSubscriber: isPrivacyProSubscriber,
            privacyProDaysSinceSubscribed: privacyProDaysSinceSubscribed,
            privacyProDaysUntilExpiry: privacyProDaysUntilExpiry,
            privacyProPurchasePlatform: privacyProPurchasePlatform,
            isPrivacyProSubscriptionActive: isPrivacyProSubscriptionActive,
            isPrivacyProSubscriptionExpiring: isPrivacyProSubscriptionExpiring,
            isPrivacyProSubscriptionExpired: isPrivacyProSubscriptionExpired,
            dismissedMessageIds: dismissedMessageIds
        )
    }

    public func evaluate(matchingAttribute: MatchingAttribute) -> EvaluationResult? {
        switch matchingAttribute {
        case let matchingAttribute as WidgetAddedMatchingAttribute:
            guard let value = matchingAttribute.value else {
                return .fail
            }

            return BooleanMatchingAttribute(value).matches(value: isWidgetInstalled)
        default:
            return commonUserAttributeMatcher.evaluate(matchingAttribute: matchingAttribute)
        }
    }

}

public struct DesktopUserAttributeMatcher: AttributeMatching {
    private let pinnedTabsCount: Int
    private let hasCustomHomePage: Bool
    private let isDuckPlayerOnboarded: Bool
    private let isDuckPlayerEnabled: Bool

    private let commonUserAttributeMatcher: CommonUserAttributeMatcher

    public init(statisticsStore: StatisticsStore,
                variantManager: VariantManager,
                emailManager: EmailManager = EmailManager(),
                bookmarksCount: Int,
                favoritesCount: Int,
                appTheme: String,
                daysSinceNetPEnabled: Int,
                isPrivacyProEligibleUser: Bool,
                isPrivacyProSubscriber: Bool,
                privacyProDaysSinceSubscribed: Int,
                privacyProDaysUntilExpiry: Int,
                privacyProPurchasePlatform: String?,
                isPrivacyProSubscriptionActive: Bool,
                isPrivacyProSubscriptionExpiring: Bool,
                isPrivacyProSubscriptionExpired: Bool,
                dismissedMessageIds: [String],
                pinnedTabsCount: Int,
                hasCustomHomePage: Bool,
                isDuckPlayerOnboarded: Bool,
                isDuckPlayerEnabled: Bool
    ) {
        self.pinnedTabsCount = pinnedTabsCount
        self.hasCustomHomePage = hasCustomHomePage
        self.isDuckPlayerOnboarded = isDuckPlayerOnboarded
        self.isDuckPlayerEnabled = isDuckPlayerEnabled

        commonUserAttributeMatcher = .init(
            statisticsStore: statisticsStore,
            variantManager: variantManager,
            emailManager: emailManager,
            bookmarksCount: bookmarksCount,
            favoritesCount: favoritesCount,
            appTheme: appTheme,
            daysSinceNetPEnabled: daysSinceNetPEnabled,
            isPrivacyProEligibleUser: isPrivacyProEligibleUser,
            isPrivacyProSubscriber: isPrivacyProSubscriber,
            privacyProDaysSinceSubscribed: privacyProDaysSinceSubscribed,
            privacyProDaysUntilExpiry: privacyProDaysUntilExpiry,
            privacyProPurchasePlatform: privacyProPurchasePlatform,
            isPrivacyProSubscriptionActive: isPrivacyProSubscriptionActive,
            isPrivacyProSubscriptionExpiring: isPrivacyProSubscriptionExpiring,
            isPrivacyProSubscriptionExpired: isPrivacyProSubscriptionExpired,
            dismissedMessageIds: dismissedMessageIds
        )
    }

    public func evaluate(matchingAttribute: MatchingAttribute) -> EvaluationResult? {
        switch matchingAttribute {
        case let matchingAttribute as PinnedTabsMatchingAttribute:
            if matchingAttribute.value != MatchingAttributeDefaults.intDefaultValue {
                return IntMatchingAttribute(matchingAttribute.value).matches(value: pinnedTabsCount)
            } else {
                return RangeIntMatchingAttribute(min: matchingAttribute.min, max: matchingAttribute.max).matches(value: pinnedTabsCount)
            }
        case let matchingAttribute as CustomHomePageMatchingAttribute:
            return matchingAttribute.evaluate(for: hasCustomHomePage)
        case let matchingAttribute as DuckPlayerOnboardedMatchingAttribute:
            return matchingAttribute.evaluate(for: isDuckPlayerOnboarded)
        case let matchingAttribute as DuckPlayerEnabledMatchingAttribute:
            return matchingAttribute.evaluate(for: isDuckPlayerEnabled)
        default:
            return commonUserAttributeMatcher.evaluate(matchingAttribute: matchingAttribute)
        }
    }
}

public struct CommonUserAttributeMatcher: AttributeMatching {

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
    private let daysSinceNetPEnabled: Int
    private let isPrivacyProEligibleUser: Bool
    private let isPrivacyProSubscriber: Bool
    private let privacyProDaysSinceSubscribed: Int
    private let privacyProDaysUntilExpiry: Int
    private let privacyProPurchasePlatform: String?
    private let isPrivacyProSubscriptionActive: Bool
    private let isPrivacyProSubscriptionExpiring: Bool
    private let isPrivacyProSubscriptionExpired: Bool
    private let dismissedMessageIds: [String]

    public init(statisticsStore: StatisticsStore,
                variantManager: VariantManager,
                emailManager: EmailManager = EmailManager(),
                bookmarksCount: Int,
                favoritesCount: Int,
                appTheme: String,
                daysSinceNetPEnabled: Int,
                isPrivacyProEligibleUser: Bool,
                isPrivacyProSubscriber: Bool,
                privacyProDaysSinceSubscribed: Int,
                privacyProDaysUntilExpiry: Int,
                privacyProPurchasePlatform: String?,
                isPrivacyProSubscriptionActive: Bool,
                isPrivacyProSubscriptionExpiring: Bool,
                isPrivacyProSubscriptionExpired: Bool,
                dismissedMessageIds: [String]
    ) {
        self.statisticsStore = statisticsStore
        self.variantManager = variantManager
        self.emailManager = emailManager
        self.appTheme = appTheme
        self.bookmarksCount = bookmarksCount
        self.favoritesCount = favoritesCount
        self.daysSinceNetPEnabled = daysSinceNetPEnabled
        self.isPrivacyProEligibleUser = isPrivacyProEligibleUser
        self.isPrivacyProSubscriber = isPrivacyProSubscriber
        self.privacyProDaysSinceSubscribed = privacyProDaysSinceSubscribed
        self.privacyProDaysUntilExpiry = privacyProDaysUntilExpiry
        self.privacyProPurchasePlatform = privacyProPurchasePlatform
        self.isPrivacyProSubscriptionActive = isPrivacyProSubscriptionActive
        self.isPrivacyProSubscriptionExpiring = isPrivacyProSubscriptionExpiring
        self.isPrivacyProSubscriptionExpired = isPrivacyProSubscriptionExpired
        self.dismissedMessageIds = dismissedMessageIds
    }

    // swiftlint:disable:next cyclomatic_complexity
    public func evaluate(matchingAttribute: MatchingAttribute) -> EvaluationResult? {
        switch matchingAttribute {
        case let matchingAttribute as AppThemeMatchingAttribute:
            return matchingAttribute.evaluate(for: appTheme)
        case let matchingAttribute as BookmarksMatchingAttribute:
            return matchingAttribute.evaluate(for: bookmarksCount)
        case let matchingAttribute as DaysSinceInstalledMatchingAttribute:
            guard let installDate = statisticsStore.installDate,
                  let daysSinceInstall = Calendar.current.numberOfDaysBetween(installDate, and: Date()) else {
                return .fail
            }
            return matchingAttribute.evaluate(for: daysSinceInstall)
        case let matchingAttribute as EmailEnabledMatchingAttribute:
            return matchingAttribute.evaluate(for: emailManager.isSignedIn)
        case let matchingAttribute as FavoritesMatchingAttribute:
            return matchingAttribute.evaluate(for: favoritesCount)
        case let matchingAttribute as DaysSinceNetPEnabledMatchingAttribute:
            return matchingAttribute.evaluate(for: daysSinceNetPEnabled)
        case let matchingAttribute as IsPrivacyProEligibleUserMatchingAttribute:
            return matchingAttribute.evaluate(for: isPrivacyProEligibleUser)
        case let matchingAttribute as IsPrivacyProSubscriberUserMatchingAttribute:
            return matchingAttribute.evaluate(for: isPrivacyProSubscriber)
        case let matchingAttribute as PrivacyProDaysSinceSubscribedMatchingAttribute:
            return matchingAttribute.evaluate(for: privacyProDaysSinceSubscribed)
        case let matchingAttribute as PrivacyProDaysUntilExpiryMatchingAttribute:
            return matchingAttribute.evaluate(for: privacyProDaysUntilExpiry)
        case let matchingAttribute as PrivacyProPurchasePlatformMatchingAttribute:
            return matchingAttribute.evaluate(for: privacyProPurchasePlatform ?? "")
        case let matchingAttribute as PrivacyProSubscriptionStatusMatchingAttribute:
            let mappedStatuses = (matchingAttribute.value ?? []).compactMap { status in
                return PrivacyProSubscriptionStatus(rawValue: status)
            }

            for status in mappedStatuses {
                switch status {
                case .active: if isPrivacyProSubscriptionActive { return .match }
                case .expiring: if isPrivacyProSubscriptionExpiring { return .match }
                case .expired: if isPrivacyProSubscriptionExpired { return .match }
                }
            }

            return .fail
        case let matchingAttribute as InteractedWithMessageMatchingAttribute:
            if dismissedMessageIds.contains(where: { messageId in
                StringArrayMatchingAttribute(matchingAttribute.value).matches(value: messageId) == .match
            }) {
                return .match
            } else {
                return .fail
            }
        default:
            assertionFailure("Could not find matching attribute")
            return nil
        }
    }

}
