//
//  UserAttributeMatcher.swift
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
import BrowserServicesKit

public struct UserAttributeMatcher: AttributeMatcher {

    private let statisticsStore: StatisticsStore
    private let variantManager: VariantManager
    private let emailManager: EmailManager
    private let appTheme: String
    private let bookmarksCount: Int
    private let favoritesCount: Int
    private let isWidgetInstalled: Bool

    public init(statisticsStore: StatisticsStore,
                variantManager: VariantManager,
                emailManager: EmailManager = EmailManager(),
                bookmarksCount: Int,
                favoritesCount: Int,
                appTheme: String,
                isWidgetInstalled: Bool
	) {
        self.statisticsStore = statisticsStore
        self.variantManager = variantManager
		self.emailManager = emailManager
        self.appTheme = appTheme
        self.bookmarksCount = bookmarksCount
        self.favoritesCount = favoritesCount
        self.isWidgetInstalled = isWidgetInstalled
    }

    // swiftlint:disable cyclomatic_complexity
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
        default:
            return nil
        }
    }
    // swiftlint:enable cyclomatic_complexity
}
