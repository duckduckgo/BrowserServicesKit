//
//  RemoteMessagingStoreTests.swift
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

import CoreData
import Foundation
import Persistence
import XCTest
@testable import RemoteMessaging

class RemoteMessagingStoreTests: XCTestCase {

    static let userDefaultsSuiteName = "remote-messaging-store-tests"

    private var store: RemoteMessagingStore!
    private let notificationCenter = NotificationCenter()
    private var defaults: UserDefaults!
    var remoteMessagingDatabase: CoreDataDatabase!
    var location: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundle = RemoteMessaging.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "RemoteMessaging") else {
            XCTFail("Failed to load model")
            return
        }
        remoteMessagingDatabase = CoreDataDatabase(name: type(of: self).description(), containerLocation: location, model: model)
        remoteMessagingDatabase.loadStore()

        store = RemoteMessagingStore(
            database: remoteMessagingDatabase,
            notificationCenter: notificationCenter,
            errorEvents: nil
        )

        defaults = UserDefaults(suiteName: Self.userDefaultsSuiteName)!
        defaults.removePersistentDomain(forName: Self.userDefaultsSuiteName)
    }

    override func tearDownWithError() throws {
        store = nil

        try? remoteMessagingDatabase.tearDown(deleteStores: true)
        remoteMessagingDatabase = nil
        try? FileManager.default.removeItem(at: location)

        try super.tearDownWithError()
    }

    // Tests:
    // 1. saveProcessedResult()
    // 2. fetch RemoteMessagingConfig and RemoteMessage successfully returned from save in step 1
    // 3. NSNotification RemoteMessagesDidChange is posted
    func testWhenSaveProcessedResultThenFetchRemoteConfigAndMessageExistsAndNotificationSent() throws {
        let expectation = XCTNSNotificationExpectation(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange,
                                                       object: nil, notificationCenter: notificationCenter)

        _ = try saveProcessedResultFetchRemoteMessage()

        // 3. NSNotification RemoteMessagesDidChange is posted
        wait(for: [expectation], timeout: 10)
    }

    func saveProcessedResultFetchRemoteMessage() throws -> RemoteMessageModel {
        let processorResult = try processorResult()
        // 1. saveProcessedResult()
        store.saveProcessedResult(processorResult)

        // 2. fetch RemoteMessagingConfig and RemoteMessage successfully returned from save in step 1
        let config = store.fetchRemoteMessagingConfig()
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.version, processorResult.version)
        guard let remoteMessage = store.fetchScheduledRemoteMessage() else {
            XCTFail("No remote message found")
            return RemoteMessageModel(id: "", content: nil, matchingRules: [], exclusionRules: [])
        }

        XCTAssertNotNil(remoteMessage)
        XCTAssertEqual(remoteMessage, processorResult.message)
        return remoteMessage
    }

    func testWhenHasNotShownMessageThenReturnFalse() throws {
        let remoteMessage = try saveProcessedResultFetchRemoteMessage()
        XCTAssertFalse(store.hasShownRemoteMessage(withId: remoteMessage.id))
    }

    func testWhenUpdateRemoteMessageAsShownMessageThenHasShownIsTrue() throws {
        let remoteMessage = try saveProcessedResultFetchRemoteMessage()
        store.updateRemoteMessage(withId: remoteMessage.id, asShown: true)
        XCTAssertTrue(store.hasShownRemoteMessage(withId: remoteMessage.id))
    }

    func testWhenUpdateRemoteMessageAsShownFalseThenHasShownIsFalse() throws {
        let remoteMessage = try saveProcessedResultFetchRemoteMessage()
        store.updateRemoteMessage(withId: remoteMessage.id, asShown: false)
        XCTAssertFalse(store.hasShownRemoteMessage(withId: remoteMessage.id))
    }

    func testWhenDismissRemoteMessageThenFetchedMessageHasDismissedState() throws {
        let remoteMessage = try saveProcessedResultFetchRemoteMessage()

        store.dismissRemoteMessage(withId: remoteMessage.id)

        guard let fetchedRemoteMessage = store.fetchRemoteMessage(withId: remoteMessage.id) else {
            XCTFail("No remote message found")
            return
        }

        XCTAssertEqual(fetchedRemoteMessage.id, remoteMessage.id)
        XCTAssertTrue(store.hasDismissedRemoteMessage(withId: fetchedRemoteMessage.id))
    }

    func testFetchDismissedRemoteMessageIds() throws {
        let remoteMessage = try saveProcessedResultFetchRemoteMessage()

        store.dismissRemoteMessage(withId: remoteMessage.id)

        let dismissedRemoteMessageIds = store.fetchDismissedRemoteMessageIds()
        XCTAssertEqual(dismissedRemoteMessageIds.count, 1)
        XCTAssertEqual(dismissedRemoteMessageIds.first, remoteMessage.id)
    }

    func decodeJson(fileName: String) throws -> RemoteMessageResponse.JsonRemoteMessagingConfig {
        let resourceURL = Bundle.module.resourceURL!.appendingPathComponent("remote-messaging-config-example.json", conformingTo: .json)

        let validJson = try Data(contentsOf: resourceURL)
        let remoteMessagingConfig = try JSONDecoder().decode(RemoteMessageResponse.JsonRemoteMessagingConfig.self, from: validJson)
        XCTAssertNotNil(remoteMessagingConfig)

        return remoteMessagingConfig
    }

    func processorResult() throws -> RemoteMessagingConfigProcessor.ProcessorResult {
        let jsonRemoteMessagingConfig = try decodeJson(fileName: "remote-messaging-config-example.json")
        let remoteMessagingConfigMatcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: AppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
                userAttributeMatcher: MobileUserAttributeMatcher(
                    statisticsStore: MockStatisticsStore(),
                    variantManager: MockVariantManager(),
                    bookmarksCount: 0,
                    favoritesCount: 0,
                    appTheme: "light",
                    isWidgetInstalled: false,
                    daysSinceNetPEnabled: -1,
                    isPrivacyProEligibleUser: false,
                    isPrivacyProSubscriber: false,
                    privacyProDaysSinceSubscribed: -1,
                    privacyProDaysUntilExpiry: -1,
                    privacyProPurchasePlatform: nil,
                    isPrivacyProSubscriptionActive: false,
                    isPrivacyProSubscriptionExpiring: false,
                    isPrivacyProSubscriptionExpired: false,
                    dismissedMessageIds: []
                ),
                percentileStore: RemoteMessagingPercentileUserDefaultsStore(userDefaults: self.defaults),
                surveyActionMapper: MockRemoteMessagingSurveyActionMapper(),
                dismissedMessageIds: []
        )

        let processor = RemoteMessagingConfigProcessor(remoteMessagingConfigMatcher: remoteMessagingConfigMatcher)
        let config: RemoteMessagingConfig = RemoteMessagingConfig(version: jsonRemoteMessagingConfig.version - 1,
                                                                  invalidate: false,
                                                                  evaluationTimestamp: Date())

        if let processorResult = processor.process(jsonRemoteMessagingConfig: jsonRemoteMessagingConfig, currentConfig: config) {
            return processorResult
        } else {
            XCTFail("Processor result message is nil")
            return RemoteMessagingConfigProcessor.ProcessorResult(version: 0, message: nil)
        }
    }
}

private final class MockRemoteMessagingSurveyActionMapper: RemoteMessagingSurveyActionMapping {

    func add(parameters: [RemoteMessagingSurveyActionParameter], to url: URL) -> URL {
        return url
    }

}
