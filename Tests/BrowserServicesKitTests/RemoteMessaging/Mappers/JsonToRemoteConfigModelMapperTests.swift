//
//  JsonToRemoteConfigModelMapperTests.swift
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
@testable import BrowserServicesKit
@testable import RemoteMessaging

class JsonToRemoteConfigModelMapperTests: XCTestCase {

    private var data = JsonTestDataLoader()

    func testWhenValidJsonParsedThenMessagesMappedIntoRemoteConfig() throws {
        let config = try decodeAndMapJson(fileName: "Resources/remote-messaging-config.json")
        XCTAssertEqual(config.messages.count, 7)

        XCTAssertEqual(config.messages[0], RemoteMessageModel(
                id: "8274589c-8aeb-4322-a737-3852911569e3",
                content: .bigSingleAction(titleText: "title", descriptionText: "description", placeholder: .announce,
                                          primaryActionText: "Ok", primaryAction: .url(value: "https://duckduckgo.com")),
                matchingRules: [],
                exclusionRules: [])
        )

        XCTAssertEqual(config.messages[1], RemoteMessageModel(
                id: "8274589c-8aeb-4322-a737-3852911569e3",
                content: .bigSingleAction(titleText: "Kedvenc hozzáadása", descriptionText: "Kedvenc eltávolítása", placeholder: .ddgAnnounce,
                                          primaryActionText: "Ok", primaryAction: .url(value: "https://duckduckgo.com")),
                matchingRules: [],
                exclusionRules: [])
        )

        XCTAssertEqual(config.messages[2], RemoteMessageModel(
                id: "26780792-49fe-4e25-ae27-aa6a2e6f013b",
                content: .small(titleText: "Here goes a title", descriptionText: "description"),
                matchingRules: [5, 6],
                exclusionRules: [7, 8, 9])
        )

        XCTAssertEqual(config.messages[3], RemoteMessageModel(
                id: "c3549d64-b388-41d8-9649-33e6e2674e8e",
                content: .medium(titleText: "Here goes a title", descriptionText: "description", placeholder: .criticalUpdate),
                matchingRules: [],
                exclusionRules: [])
        )

        XCTAssertEqual(config.messages[4], RemoteMessageModel(
                id: "c2d0a1f1-6157-434f-8145-38416037d339",
                content: .bigTwoAction(titleText: "Here goes a title", descriptionText: "description", placeholder: .appUpdate,
                                       primaryActionText: "Ok", primaryAction: .appStore,
                                       secondaryActionText: "Cancel", secondaryAction: .dismiss),
                matchingRules: [],
                exclusionRules: [])
        )

        XCTAssertEqual(config.messages[5], RemoteMessageModel(
            id: "96EEA91B-030D-41E5-95A7-F11C1952A5FF",
            content: .bigTwoAction(titleText: "Here goes a title", descriptionText: "description", placeholder: .newForMacAndWindows,
                                   primaryActionText: "Ok", primaryAction: .share(value: "https://duckduckgo.com/app",
                                                                                  title: "Share Title"),
                                   secondaryActionText: "Cancel", secondaryAction: .dismiss),
            matchingRules: [],
            exclusionRules: [])
        )

        XCTAssertEqual(config.messages[6], RemoteMessageModel(
            id: "6E58D3DA-AB9D-47A4-87B7-B8AF830BFB5E",
            content: .promoSingleAction(titleText: "Promo Title", descriptionText: "Promo Description", placeholder: .newForMacAndWindows,
                                        actionText: "Promo Action", action: .dismiss),
            matchingRules: [],
            exclusionRules: [])
        )

    }

    func testWhenValidJsonParsedThenRulesMappedIntoRemoteConfig() throws {
        let config = try decodeAndMapJson(fileName: "Resources/remote-messaging-config.json")
        XCTAssertTrue(config.rules.count == 3)

        let rule5 = config.rules.filter { $0.key == 5 }.first
        XCTAssertNotNil(rule5)
        XCTAssertTrue(rule5?.value.count == 16)
        var attribs = rule5?.value.filter { $0 is LocaleMatchingAttribute }
        XCTAssertEqual(attribs?.count, 1)
        XCTAssertEqual(attribs?.first as? LocaleMatchingAttribute, LocaleMatchingAttribute(value: ["en-US", "en-GB"], fallback: true))

        let rule6 = config.rules.filter { $0.key == 6 }.first
        XCTAssertNotNil(rule6)
        XCTAssertTrue(rule6?.value.count == 1)
        attribs = rule6?.value.filter { $0 is LocaleMatchingAttribute }
        XCTAssertEqual(attribs?.count, 1)
        XCTAssertEqual(attribs?.first as? LocaleMatchingAttribute, LocaleMatchingAttribute(value: ["en-GB"], fallback: nil))

        let rule7 = config.rules.filter { $0.key == 7 }.first
        XCTAssertNotNil(rule7)
        XCTAssertTrue(rule7?.value.count == 1)
        attribs = rule7?.value.filter { $0 is WidgetAddedMatchingAttribute }
        XCTAssertEqual(attribs?.count, 1)
        XCTAssertEqual(attribs?.first as? WidgetAddedMatchingAttribute, WidgetAddedMatchingAttribute(value: false, fallback: nil))
    }

    func testWhenJsonMessagesHaveUnknownTypesThenMessagesNotMappedIntoConfig() throws {
        let config = try decodeAndMapJson(fileName: "Resources/remote-messaging-config-unsupported-items.json")
        let countValidContent = config.messages.filter { $0.content != nil }.count
        XCTAssertEqual(countValidContent, 1)
    }

    func testWhenJsonMessagesHaveUnknownTypesThenRulesMappedIntoConfig() throws {
        let config = try decodeAndMapJson(fileName: "Resources/remote-messaging-config-unsupported-items.json")
        XCTAssertTrue(config.rules.count == 2)

        let rule6 = config.rules.filter { $0.key == 6 }.first
        XCTAssertNotNil(rule6)
        var attribs = rule6?.value.filter { $0 is UnknownMatchingAttribute }
        XCTAssertEqual(attribs?.count, 1)
        XCTAssertEqual(attribs?.first as? UnknownMatchingAttribute, UnknownMatchingAttribute(fallback: true))

        let rule7 = config.rules.filter { $0.key == 7 }.first
        XCTAssertNotNil(rule7)
        attribs = rule7?.value.filter { $0 is WidgetAddedMatchingAttribute }
        XCTAssertEqual(attribs?.count, 1)
        XCTAssertEqual(attribs?.first as? WidgetAddedMatchingAttribute, WidgetAddedMatchingAttribute(value: true, fallback: nil))
    }

    func testWhenJsonAttributeMissingThenUnknownIntoConfig() throws {
        let validJson = data.fromJsonFile("Resources/remote-messaging-config-malformed.json")
        let remoteMessagingConfig = try JSONDecoder().decode(RemoteMessageResponse.JsonRemoteMessagingConfig.self, from: validJson)
        XCTAssertNotNil(remoteMessagingConfig)
        let config = JsonToRemoteConfigModelMapper.mapJson(remoteMessagingConfig: remoteMessagingConfig)
        XCTAssertTrue(config.rules.count == 2)

        let rule6 = config.rules.filter { $0.key == 6 }.first
        XCTAssertNotNil(rule6)
        XCTAssertEqual(rule6?.value.filter { $0 is LocaleMatchingAttribute }.count, 1)
        XCTAssertEqual(rule6?.value.filter { $0 is OSMatchingAttribute }.count, 1)
        XCTAssertEqual(rule6?.value.filter { $0 is UnknownMatchingAttribute }.count, 1)
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
