//
//  RemoteMessagingConfigMatcherTests.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

import XCTest
@testable import Common
@testable import BrowserServicesKit
@testable import RemoteMessaging

class RemoteMessagingConfigMatcherTests: XCTestCase {

    private var data = JsonTestDataLoader()
    private var matcher: RemoteMessagingConfigMatcher!

    override func setUpWithError() throws {
        let emailManagerStorage = MockEmailManagerStorage()

        // EmailEnabledMatchingAttribute isSignedIn = true
        emailManagerStorage.mockUsername = "username"
        emailManagerStorage.mockToken = "token"

        let emailManager = EmailManager(storage: emailManagerStorage)
        matcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: AppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
                userAttributeMatcher: UserAttributeMatcher(statisticsStore: MockStatisticsStore(),
                                                           variantManager: MockVariantManager(),
                                                           emailManager: emailManager,
                                                           bookmarksCount: 10,
                                                           favoritesCount: 0,
                                                           appTheme: "light",
                                                           isWidgetInstalled: false),
                dismissedMessageIds: []
        )
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()

        matcher = nil
    }

    func testWhenEmptyConfigThenReturnNull() throws {
        let emptyConfig = RemoteConfigModel(messages: [], rules: [:])

        XCTAssertNil(matcher.evaluate(remoteConfig: emptyConfig))
    }

    func testWhenNoMatchingRulesThenReturnFirstMessage() throws {
        let noRulesRemoteConfig = RemoteConfigModel(messages: [mediumMessage(matchingRules: [1], exclusionRules: []),
                                                          mediumMessage(matchingRules: [], exclusionRules: [])],
                                               rules: [:])
        XCTAssertEqual(matcher.evaluate(remoteConfig: noRulesRemoteConfig), mediumMessage(matchingRules: [], exclusionRules: []))
    }

    func testWhenNotExistingRuleThenReturnSkipMessage() throws {
        let noRulesRemoteConfig = RemoteConfigModel(messages: [mediumMessage(matchingRules: [1], exclusionRules: []),
                                                          mediumMessage(matchingRules: [], exclusionRules: [])],
                                               rules: [:])

        XCTAssertEqual(matcher.evaluate(remoteConfig: noRulesRemoteConfig), mediumMessage(matchingRules: [], exclusionRules: []))
    }

    func testWhenNoMessagesThenReturnNull() throws {
        let os = ProcessInfo().operatingSystemVersion
        let noRulesRemoteConfig = RemoteConfigModel(messages: [],
                                               rules: [1: [OSMatchingAttribute(min: "0.0", max: String(os.majorVersion + 1), fallback: nil)]])

        XCTAssertNil(matcher.evaluate(remoteConfig: noRulesRemoteConfig))
    }

    func testWhenDeviceDoesNotMatchMessageRulesThenReturnNull() throws {
        let os = ProcessInfo().operatingSystemVersion
        let remoteConfig = RemoteConfigModel(messages: [mediumMessage(matchingRules: [1], exclusionRules: []),
                                                   mediumMessage(matchingRules: [1], exclusionRules: [])],
                                        rules: [1: [OSMatchingAttribute(min: "0.0", max: String(os.majorVersion - 1), fallback: nil)]])

        XCTAssertNil(matcher.evaluate(remoteConfig: remoteConfig))
    }

    func testWhenNoMatchingRulesThenReturnFirstNonExcludedMessage() {
        let remoteConfig = RemoteConfigModel(messages: [mediumMessage(matchingRules: [], exclusionRules: [2]),
                                                   mediumMessage(matchingRules: [], exclusionRules: [3])],
                                        rules: [1: [OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)],
                                                2: [LocaleMatchingAttribute(value: [LocaleMatchingAttribute.localeIdentifierAsJsonFormat(Locale.current.identifier)], fallback: nil)],
                                                3: [EmailEnabledMatchingAttribute(value: false, fallback: nil)]])

        XCTAssertEqual(matcher.evaluate(remoteConfig: remoteConfig), mediumMessage(matchingRules: [], exclusionRules: [3]))
    }

    func testWhenMatchingMessageShouldBeExcludedThenReturnNull() {
        matcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: AppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
                deviceAttributeMatcher: DeviceAttributeMatcher(osVersion: AppVersion.shared.osVersion, locale: "en-US"),
                userAttributeMatcher: UserAttributeMatcher(statisticsStore: MockStatisticsStore(),
                                                           variantManager: MockVariantManager(),
                                                           bookmarksCount: 0,
                                                           favoritesCount: 0,
                                                           appTheme: "light",
                                                           isWidgetInstalled: false),
                dismissedMessageIds: [])

        let remoteConfig = RemoteConfigModel(messages: [mediumMessage(matchingRules: [1], exclusionRules: [2])],
                                        rules: [1: [OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)],
                                                2: [LocaleMatchingAttribute(value: ["en-US"], fallback: nil)]])

        XCTAssertNil(matcher.evaluate(remoteConfig: remoteConfig))
    }

    func testWhenMatchingMessageShouldBeExcludedByOneOfMultipleRulesThenReturnNull() {
        let remoteConfig = RemoteConfigModel(messages: [mediumMessage(matchingRules: [1], exclusionRules: [4]),
                                                   mediumMessage(matchingRules: [1], exclusionRules: [2, 3]),
                                                   mediumMessage(matchingRules: [1], exclusionRules: [2, 3, 4]),
                                                   mediumMessage(matchingRules: [1], exclusionRules: [2, 4]),
                                                   mediumMessage(matchingRules: [1], exclusionRules: [4])],
                                        rules: [1: [OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)],
                                                2: [EmailEnabledMatchingAttribute(value: true, fallback: nil), BookmarksMatchingAttribute(max: 10, fallback: nil)],
                                                3: [EmailEnabledMatchingAttribute(value: true, fallback: nil), BookmarksMatchingAttribute(max: 10, fallback: nil)],
                                                4: [OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)],
                                                5: [EmailEnabledMatchingAttribute(value: true, fallback: nil)]])

        XCTAssertNil(matcher.evaluate(remoteConfig: remoteConfig))
    }

    func testWhenMultipleMatchingMessagesAndSomeExcludedThenReturnFirstNonExcludedMatch() {
        let remoteConfig = RemoteConfigModel(messages: [mediumMessage(matchingRules: [1], exclusionRules: [2]),
                                                   mediumMessage(matchingRules: [1], exclusionRules: [2]),
                                                   mediumMessage(matchingRules: [1], exclusionRules: [])],
                                        rules: [1: [OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)],
                                                2: [LocaleMatchingAttribute(value: [LocaleMatchingAttribute.localeIdentifierAsJsonFormat(Locale.current.identifier)], fallback: nil)]])

        XCTAssertEqual(matcher.evaluate(remoteConfig: remoteConfig), mediumMessage(matchingRules: [1], exclusionRules: []))
    }

    func testWhenMessageMatchesAndExclusionRuleFailsThenReturnMessage() {
        let remoteConfig = RemoteConfigModel(messages: [mediumMessage(matchingRules: [1], exclusionRules: [2])],
                                        rules: [1: [OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)],
                                                2: [EmailEnabledMatchingAttribute(value: false, fallback: nil)]])

        XCTAssertEqual(matcher.evaluate(remoteConfig: remoteConfig), mediumMessage(matchingRules: [1], exclusionRules: [2]))
    }

    func testWhenDeviceMatchesMessageRulesThenReturnFirstMatch() {
        let remoteConfig = RemoteConfigModel(messages: [mediumMessage(matchingRules: [1], exclusionRules: [])],
                                        rules: [1: [OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)]])

        XCTAssertEqual(matcher.evaluate(remoteConfig: remoteConfig), mediumMessage(matchingRules: [1], exclusionRules: []))
    }

    func testWhenDeviceMatchesMessageRulesForOneOfMultipleMessagesThenReturnMatch() {
        let remoteConfig = RemoteConfigModel(messages: [mediumMessage(matchingRules: [2], exclusionRules: []),
                                                   mediumMessage(matchingRules: [1, 2], exclusionRules: [])],
                                        rules: [1: [OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)],
                                                2: [EmailEnabledMatchingAttribute(value: false, fallback: nil)]])

        XCTAssertEqual(matcher.evaluate(remoteConfig: remoteConfig), mediumMessage(matchingRules: [1, 2], exclusionRules: []))
    }

    func testWhenUserDismissedMessagesAndDeviceMatchesMultipleMessagesThenReturnFirstMatchNotDismissed() {
        matcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: AppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
                userAttributeMatcher: UserAttributeMatcher(statisticsStore: MockStatisticsStore(),
                                                           variantManager: MockVariantManager(),
                                                           bookmarksCount: 10,
                                                           favoritesCount: 0,
                                                           appTheme: "light",
                                                           isWidgetInstalled: false),
                dismissedMessageIds: ["1"])

        let remoteConfig = RemoteConfigModel(messages: [mediumMessage(matchingRules: [1], exclusionRules: []),
                                                   mediumMessage(id: "2", matchingRules: [1], exclusionRules: [])],
                                        rules: [1: [OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)]])

        XCTAssertEqual(matcher.evaluate(remoteConfig: remoteConfig), mediumMessage(id: "2", matchingRules: [1], exclusionRules: []))
    }

    func testWhenDeviceMatchesAnyRuleThenReturnFirstMatch() {
        let remoteConfig = RemoteConfigModel(messages: [mediumMessage(matchingRules: [1, 2], exclusionRules: [])],
                                        rules: [1: [LocaleMatchingAttribute(value: [Locale.current.identifier], fallback: nil)],
                                                2: [OSMatchingAttribute(min: "0", max: "15", fallback: nil)]])

        XCTAssertEqual(matcher.evaluate(remoteConfig: remoteConfig), mediumMessage(matchingRules: [1, 2], exclusionRules: []))
    }

    func testWhenDeviceDoesNotMatchAnyRuleThenReturnNull() {
        let os = ProcessInfo().operatingSystemVersion
        matcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: AppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
                deviceAttributeMatcher: DeviceAttributeMatcher(osVersion: AppVersion.shared.osVersion, locale: "en-US"),
                userAttributeMatcher: UserAttributeMatcher(statisticsStore: MockStatisticsStore(),
                                                           variantManager: MockVariantManager(),
                                                           bookmarksCount: 0,
                                                           favoritesCount: 0,
                                                           appTheme: "light",
                                                           isWidgetInstalled: false),
                dismissedMessageIds: [])

        let remoteConfig = RemoteConfigModel(messages: [mediumMessage(matchingRules: [1, 2], exclusionRules: []),
                                                   mediumMessage(matchingRules: [1, 2], exclusionRules: [])],
                                        rules: [1: [OSMatchingAttribute(min: "0.0", max: String(os.majorVersion - 1), fallback: nil)],
                                                2: [OSMatchingAttribute(min: "0.0", max: String(os.majorVersion - 1), fallback: nil)]])

        XCTAssertNil(matcher.evaluate(remoteConfig: remoteConfig))
    }

    func testWhenUnknownRuleFailsThenReturnNull() {
        let remoteConfig = RemoteConfigModel(messages: [mediumMessage(matchingRules: [1], exclusionRules: []),
                                                   mediumMessage(matchingRules: [1], exclusionRules: [])],
                                        rules: [1: [UnknownMatchingAttribute(fallback: false)]])

        XCTAssertNil(matcher.evaluate(remoteConfig: remoteConfig))
    }

    func testWhenUnknownRuleMatchesThenReturnFirstMatch() {
        let remoteConfig = RemoteConfigModel(messages: [mediumMessage(matchingRules: [1], exclusionRules: []),
                                                   mediumMessage(id: "2", matchingRules: [1], exclusionRules: [])],
                                        rules: [1: [UnknownMatchingAttribute(fallback: true)]])

        XCTAssertEqual(matcher.evaluate(remoteConfig: remoteConfig), mediumMessage(matchingRules: [1], exclusionRules: []))
    }

    func mediumMessage(id: String = "1", matchingRules: [Int], exclusionRules: [Int]) -> RemoteMessageModel {
        return RemoteMessageModel(id: id,
                             content: .medium(titleText: "title", descriptionText: "description", placeholder: .announce),
                             matchingRules: matchingRules,
                             exclusionRules: exclusionRules
        )
    }

    func decodeAndMapJson(fileName: String) throws -> RemoteConfigModel {
        let validJson = data.fromJsonFile(fileName)
        let remoteMessagingConfig = try JSONDecoder().decode(RemoteMessageResponse.JsonRemoteMessagingConfig.self, from: validJson)
        XCTAssertNotNil(remoteMessagingConfig)

        let config = JsonToRemoteConfigModelMapper.mapJson(remoteMessagingConfig: remoteMessagingConfig)
        XCTAssertNotNil(config)
        return config
    }
}
