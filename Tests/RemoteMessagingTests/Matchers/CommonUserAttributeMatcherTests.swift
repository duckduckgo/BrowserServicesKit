//
//  CommonUserAttributeMatcherTests.swift
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

import BrowserServicesKit
import BrowserServicesKitTestsUtils
import Foundation
import RemoteMessagingTestsUtils
import XCTest
@testable import RemoteMessaging

class CommonUserAttributeMatcherTests: XCTestCase {

    var mockStatisticsStore: MockStatisticsStore!
    var manager: MockVariantManager!
    var emailManager: EmailManager!
    var matcher: CommonUserAttributeMatcher!
    var dateYesterday: Date!

    override func setUpWithError() throws {
        let now = Calendar.current.dateComponents(in: .current, from: Date())
        let yesterday = DateComponents(year: now.year, month: now.month, day: now.day! - 1)
        let dateYesterday = Calendar.current.date(from: yesterday)!

        mockStatisticsStore = MockStatisticsStore()
        mockStatisticsStore.atb = "v105-2"
        mockStatisticsStore.appRetentionAtb = "v105-44"
        mockStatisticsStore.searchRetentionAtb = "v105-88"
        mockStatisticsStore.installDate = dateYesterday

        manager = MockVariantManager(isSupportedReturns: true,
                                         currentVariant: MockVariant(name: "zo", weight: 44, isIncluded: { return true }, features: [.dummy]))
        let emailManagerStorage = MockEmailManagerStorage()

        // Set non-empty username and token so that emailManager's isSignedIn returns true
        emailManagerStorage.mockUsername = "username"
        emailManagerStorage.mockToken = "token"

        emailManager = EmailManager(storage: emailManagerStorage)
        setUpUserAttributeMatcher()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()

        matcher = nil
    }

    // MARK: - AppTheme

    func testWhenAppThemeMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: AppThemeMatchingAttribute(value: "default", fallback: nil)),
                       .match)
    }

    func testWhenAppThemeDoesNotMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: AppThemeMatchingAttribute(value: "light", fallback: nil)),
                       .fail)
    }

    // MARK: - Bookmarks

    func testWhenBookmarksMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: BookmarksMatchingAttribute(value: 44, fallback: nil)),
                       .match)
    }

    func testWhenBookmarksDoesNotMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: BookmarksMatchingAttribute(value: 22, fallback: nil)),
                       .fail)
    }

    func testWhenBookmarksEqualOrLowerThanMaxThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: BookmarksMatchingAttribute(max: 44, fallback: nil)),
                       .match)
    }

    func testWhenBookmarksGreaterThanMaxThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: BookmarksMatchingAttribute(max: 40, fallback: nil)),
                       .fail)
    }

    func testWhenBookmarksLowerThanMinThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: BookmarksMatchingAttribute(min: 88, fallback: nil)),
                       .fail)
    }

    func testWhenBookmarksInRangeThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: BookmarksMatchingAttribute(min: 40, max: 48, fallback: nil)),
                       .match)
    }

    func testWhenBookmarksNotInRangeThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: BookmarksMatchingAttribute(min: 47, max: 48, fallback: nil)),
                       .fail)
    }

    // MARK: - Favorites

    func testWhenFavoritesMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: FavoritesMatchingAttribute(value: 88, fallback: nil)),
                       .match)
    }

    func testWhenFavoritesDoesNotMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: FavoritesMatchingAttribute(value: 22, fallback: nil)),
                       .fail)
    }

    func testWhenFavoritesEqualOrLowerThanMaxThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: FavoritesMatchingAttribute(max: 88, fallback: nil)),
                       .match)
    }

    func testWhenFavoritesGreaterThanMaxThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: FavoritesMatchingAttribute(max: 40, fallback: nil)),
                       .fail)
    }

    func testWhenFavoritesLowerThanMinThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: FavoritesMatchingAttribute(min: 100, fallback: nil)),
                       .fail)
    }

    func testWhenFavoritesInRangeThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: FavoritesMatchingAttribute(min: 40, max: 98, fallback: nil)),
                       .match)
    }

    func testWhenFavoritesNotInRangeThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: FavoritesMatchingAttribute(min: 89, max: 98, fallback: nil)),
                       .fail)
    }

    // MARK: - DaysSinceInstalled

    func testWhenDaysSinceInstalledEqualOrLowerThanMaxThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: DaysSinceInstalledMatchingAttribute(max: 1, fallback: nil)),
                       .match)
    }

    func testWhenDaysSinceInstalledGreaterThanMaxThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: DaysSinceInstalledMatchingAttribute(max: 0, fallback: nil)),
                       .fail)
    }

    func testWhenDaysSinceInstalledEqualOrGreaterThanMinThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: DaysSinceInstalledMatchingAttribute(min: 1, fallback: nil)),
                       .match)
    }

    func testWhenDaysSinceInstalledLowerThanMinThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: DaysSinceInstalledMatchingAttribute(min: 2, fallback: nil)),
                       .fail)
    }

    func testWhenDaysSinceInstalledInRangeThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: DaysSinceInstalledMatchingAttribute(min: 0, max: 1, fallback: nil)),
                       .match)
    }

    func testWhenDaysSinceInstalledNotInRangeThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: DaysSinceInstalledMatchingAttribute(min: 2, max: 44, fallback: nil)),
                       .fail)
    }

    // MARK: - EmailEnabled

    func testWhenEmailEnabledMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: EmailEnabledMatchingAttribute(value: true, fallback: nil)),
                       .match)
    }

    func testWhenEmailEnabledDoesNotMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: EmailEnabledMatchingAttribute(value: false, fallback: nil)),
                       .fail)
    }

    // MARK: - Privacy Pro

    func testWhenDaysSinceNetPEnabledMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: DaysSinceNetPEnabledMatchingAttribute(min: 1, fallback: nil)),
                       .match)
    }

    func testWhenDaysSinceNetPEnabledDoesNotMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: DaysSinceNetPEnabledMatchingAttribute(min: 7, fallback: nil)),
                       .fail)
    }

    func testWhenIsPrivacyProEligibleUserMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: IsPrivacyProEligibleUserMatchingAttribute(value: true, fallback: nil)),
                       .match)
    }

    func testWhenIsPrivacyProEligibleUserDoesNotMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: IsPrivacyProEligibleUserMatchingAttribute(value: false, fallback: nil)),
                       .fail)
    }

    func testWhenIsPrivacyProSubscriberMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: IsPrivacyProSubscriberUserMatchingAttribute(value: true, fallback: nil)),
                       .match)
    }

    func testWhenIsPrivacyProSubscriberDoesNotMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: IsPrivacyProSubscriberUserMatchingAttribute(value: false, fallback: nil)),
                       .fail)
    }

    func testWhenPrivacyProPurchasePlatformMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(
            matchingAttribute: PrivacyProPurchasePlatformMatchingAttribute(
                value: ["apple"], fallback: nil
            )
        ), .match)
    }

    func testWhenPrivacyProPurchasePlatformDoesNotMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(
            matchingAttribute: PrivacyProPurchasePlatformMatchingAttribute(
                value: ["stripe"], fallback: nil
            )
        ), .fail)
    }

    func testWhenPrivacyProSubscriptionStatusMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(
            matchingAttribute: PrivacyProSubscriptionStatusMatchingAttribute(value: ["active"], fallback: nil)
        ), .match)
    }

    func testWhenPrivacyProSubscriptionStatusHasMultipleAttributesAndOneMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(
            matchingAttribute: PrivacyProSubscriptionStatusMatchingAttribute(value: ["active", "expiring", "expired"], fallback: nil)
        ), .match)
    }

    func testWhenPrivacyProSubscriptionStatusDoesNotMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(
            matchingAttribute: PrivacyProSubscriptionStatusMatchingAttribute(value: ["expiring"], fallback: nil)
        ), .fail)
    }

    func testWhenPrivacyProSubscriptionStatusHasUnsupportedStatusThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(
            matchingAttribute: PrivacyProSubscriptionStatusMatchingAttribute(value: ["unsupported_status"], fallback: nil)
        ), .fail)
    }

    func testWhenOneDismissedMessageIdMatchesThenReturnMatch() throws {
        setUpUserAttributeMatcher(dismissedMessageIds: ["1"])
        XCTAssertEqual(matcher.evaluate(
            matchingAttribute: InteractedWithMessageMatchingAttribute(value: ["1", "2", "3"], fallback: nil)
        ), .match)
    }

    func testWhenAllDismissedMessageIdsMatchThenReturnMatch() throws {
        setUpUserAttributeMatcher(dismissedMessageIds: ["1", "2", "3"])
        XCTAssertEqual(matcher.evaluate(
            matchingAttribute: InteractedWithMessageMatchingAttribute(value: ["1", "2", "3"], fallback: nil)
        ), .match)
    }

    func testWhenNoDismissedMessageIdsMatchThenReturnFail() throws {
        setUpUserAttributeMatcher(dismissedMessageIds: ["1", "2", "3"])
        XCTAssertEqual(matcher.evaluate(
            matchingAttribute: InteractedWithMessageMatchingAttribute(value: ["4", "5"], fallback: nil)
        ), .fail)
    }

    func testWhenHaveDismissedMessageIdsAndMatchAttributeIsEmptyThenReturnFail() throws {
        setUpUserAttributeMatcher(dismissedMessageIds: ["1", "2", "3"])
        XCTAssertEqual(matcher.evaluate(matchingAttribute: InteractedWithMessageMatchingAttribute(value: [], fallback: nil)), .fail)
    }

    func testWhenHaveNoDismissedMessageIdsAndMatchAttributeIsNotEmptyThenReturnFail() throws {
        setUpUserAttributeMatcher(dismissedMessageIds: [])
        XCTAssertEqual(matcher.evaluate(
            matchingAttribute: InteractedWithMessageMatchingAttribute(value: ["1", "2"], fallback: nil)
        ), .fail)
    }

    private func setUpUserAttributeMatcher(dismissedMessageIds: [String] = []) {
        matcher = CommonUserAttributeMatcher(
            statisticsStore: mockStatisticsStore,
            variantManager: manager,
            emailManager: emailManager,
            bookmarksCount: 44,
            favoritesCount: 88,
            appTheme: "default",
            daysSinceNetPEnabled: 3,
            isPrivacyProEligibleUser: true,
            isPrivacyProSubscriber: true,
            privacyProDaysSinceSubscribed: 5,
            privacyProDaysUntilExpiry: 25,
            privacyProPurchasePlatform: "apple",
            isPrivacyProSubscriptionActive: true,
            isPrivacyProSubscriptionExpiring: false,
            isPrivacyProSubscriptionExpired: false,
            isDuckPlayerOnboarded: false,
            isDuckPlayerEnabled: false,
            dismissedMessageIds: dismissedMessageIds
        )
    }
}
