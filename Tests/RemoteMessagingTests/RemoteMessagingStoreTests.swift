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

import BrowserServicesKitTestsUtils
import CoreData
import Foundation
import Persistence
import RemoteMessagingTestsUtils
import TestUtils
import XCTest
@testable import RemoteMessaging

class RemoteMessagingStoreTests: XCTestCase {

    var store: RemoteMessagingStore!
    let notificationCenter = NotificationCenter()
    var defaults: MockKeyValueStore!
    var availabilityProvider: MockRemoteMessagingAvailabilityProvider!
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

        availabilityProvider = MockRemoteMessagingAvailabilityProvider()

        store = RemoteMessagingStore(
            database: remoteMessagingDatabase,
            notificationCenter: notificationCenter,
            errorEvents: nil,
            remoteMessagingAvailabilityProvider: availabilityProvider
        )

        defaults = MockKeyValueStore()
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
            return RemoteMessageModel(id: "", content: nil, matchingRules: [], exclusionRules: [], isMetricsEnabled: true)
        }

        XCTAssertNotNil(remoteMessage)
        XCTAssertEqual(remoteMessage, processorResult.message)
        return remoteMessage
    }

    func testWhenHasNotShownMessageThenReturnFalse() throws {
        let remoteMessage = try saveProcessedResultFetchRemoteMessage()
        XCTAssertFalse(store.hasShownRemoteMessage(withID: remoteMessage.id))
    }

    func testWhenUpdateRemoteMessageAsShownMessageThenHasShownIsTrue() throws {
        let remoteMessage = try saveProcessedResultFetchRemoteMessage()
        store.updateRemoteMessage(withID: remoteMessage.id, asShown: true)
        XCTAssertTrue(store.hasShownRemoteMessage(withID: remoteMessage.id))
    }

    func testWhenUpdateRemoteMessageAsShownFalseThenHasShownIsFalse() throws {
        let remoteMessage = try saveProcessedResultFetchRemoteMessage()
        store.updateRemoteMessage(withID: remoteMessage.id, asShown: false)
        XCTAssertFalse(store.hasShownRemoteMessage(withID: remoteMessage.id))
    }

    func testWhenDismissRemoteMessageThenFetchedMessageHasDismissedState() throws {
        let remoteMessage = try saveProcessedResultFetchRemoteMessage()

        store.dismissRemoteMessage(withID: remoteMessage.id)

        guard let fetchedRemoteMessage = store.fetchRemoteMessage(withID: remoteMessage.id) else {
            XCTFail("No remote message found")
            return
        }

        XCTAssertEqual(fetchedRemoteMessage.id, remoteMessage.id)
        XCTAssertTrue(store.hasDismissedRemoteMessage(withID: fetchedRemoteMessage.id))
    }

    func testFetchDismissedRemoteMessageIds() throws {
        let remoteMessage = try saveProcessedResultFetchRemoteMessage()

        store.dismissRemoteMessage(withID: remoteMessage.id)

        let dismissedRemoteMessageIds = store.fetchDismissedRemoteMessageIDs()
        XCTAssertEqual(dismissedRemoteMessageIds.count, 1)
        XCTAssertEqual(dismissedRemoteMessageIds.first, remoteMessage.id)
    }

    // MARK: - Feature Flag

    func testWhenFeatureFlagIsDisabledThenScheduledRemoteMessagesAreDeleted() throws {
        _ = try saveProcessedResultFetchRemoteMessage()
        XCTAssertNotNil(store.fetchScheduledRemoteMessage())

        let expectation = XCTNSNotificationExpectation(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange,
                                                       object: nil, notificationCenter: notificationCenter)

        availabilityProvider.isRemoteMessagingAvailable = false
        XCTAssertNil(store.fetchScheduledRemoteMessage())

        wait(for: [expectation], timeout: 1)

        // Re-enabling remote messaging doesn't trigger a refetch on a Store level so no new scheduled messages should appear
        availabilityProvider.isRemoteMessagingAvailable = true
        XCTAssertNil(store.fetchScheduledRemoteMessage())
    }

    func testWhenFeatureFlagIsDisabledAndThereWereNoMessagesThenNotificationIsNotSent() throws {
        XCTAssertNil(store.fetchScheduledRemoteMessage())

        let expectation = XCTNSNotificationExpectation(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange,
                                                       object: nil, notificationCenter: notificationCenter)
        expectation.isInverted = true

        availabilityProvider.isRemoteMessagingAvailable = false
        XCTAssertNil(store.fetchScheduledRemoteMessage())

        wait(for: [expectation], timeout: 1)
    }

    func testWhenFeatureFlagIsDisabledAndThereWereNoScheduledMessagesThenNotificationIsNotSent() throws {
        _ = try saveProcessedResultFetchRemoteMessage()

        // Dismiss all available messages
        while let remoteMessage = store.fetchScheduledRemoteMessage() {
            store.dismissRemoteMessage(withID: remoteMessage.id)
        }

        let expectation = XCTNSNotificationExpectation(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange,
                                                       object: nil, notificationCenter: notificationCenter)
        expectation.isInverted = true

        availabilityProvider.isRemoteMessagingAvailable = false
        XCTAssertNil(store.fetchScheduledRemoteMessage())

        wait(for: [expectation], timeout: 1)
    }

    func testWhenFeatureFlagIsDisabledThenProcessedResultIsNotSaved() throws {
        availabilityProvider.isRemoteMessagingAvailable = false

        let expectation = XCTNSNotificationExpectation(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange,
                                                       object: nil, notificationCenter: notificationCenter)
        expectation.isInverted = true

        let processorResult = try processorResult()
        store.saveProcessedResult(processorResult)

        wait(for: [expectation], timeout: 1)
    }

    func testWhenFeatureFlagIsDisabledThenFetchScheduledRemoteMessageReturnsNil() throws {
        _ = try saveProcessedResultFetchRemoteMessage()
        availabilityProvider.isRemoteMessagingAvailable = false

        XCTAssertNil(store.fetchScheduledRemoteMessage())
    }

    func testWhenFeatureFlagIsDisabledThenFetchRemoteMessagingConfigReturnsNil() throws {
        _ = try saveProcessedResultFetchRemoteMessage()
        availabilityProvider.isRemoteMessagingAvailable = false

        XCTAssertNil(store.fetchRemoteMessagingConfig())
    }

    func testWhenFeatureFlagIsDisabledThenFetchedMessageReturnsNil() throws {
        let remoteMessage = try saveProcessedResultFetchRemoteMessage()

        availabilityProvider.isRemoteMessagingAvailable = false

        XCTAssertNil(store.fetchRemoteMessage(withID: remoteMessage.id))
    }

    func testWhenFeatureFlagIsDisabledThenUpdateShownFlagHasNoEffect() throws {
        let remoteMessage = try saveProcessedResultFetchRemoteMessage()
        availabilityProvider.isRemoteMessagingAvailable = false

        store.updateRemoteMessage(withID: remoteMessage.id, asShown: true)

        XCTAssertFalse(store.hasShownRemoteMessage(withID: remoteMessage.id))
    }

    func testWhenFeatureFlagIsDisabledThenHasShownMessageReturnFalse() throws {
        let remoteMessage = try saveProcessedResultFetchRemoteMessage()
        store.updateRemoteMessage(withID: remoteMessage.id, asShown: true)
        availabilityProvider.isRemoteMessagingAvailable = false

        XCTAssertFalse(store.hasShownRemoteMessage(withID: remoteMessage.id))
    }

    func testWhenFeatureFlagIsDisabledThenDismissingRemoteMessageHasNoEffect() throws {
        let remoteMessage = try saveProcessedResultFetchRemoteMessage()

        availabilityProvider.isRemoteMessagingAvailable = false
        store.dismissRemoteMessage(withID: remoteMessage.id)

        XCTAssertEqual(store.fetchDismissedRemoteMessageIDs(), [])
    }

    func testWhenFeatureFlagIsDisabledThenHasDismissedRemoteMessageReturnsFalse() throws {
        let remoteMessage = try saveProcessedResultFetchRemoteMessage()

        store.dismissRemoteMessage(withID: remoteMessage.id)
        availabilityProvider.isRemoteMessagingAvailable = false

        XCTAssertEqual(store.hasDismissedRemoteMessage(withID: remoteMessage.id), false)
    }

    // MARK: -

    func decodeJson(fileName: String) throws -> RemoteMessageResponse.JsonRemoteMessagingConfig {
        let resourceURL = Bundle.module.resourceURL!.appendingPathComponent(fileName, conformingTo: .json)

        let validJson = try Data(contentsOf: resourceURL)
        let remoteMessagingConfig = try JSONDecoder().decode(RemoteMessageResponse.JsonRemoteMessagingConfig.self, from: validJson)
        XCTAssertNotNil(remoteMessagingConfig)

        return remoteMessagingConfig
    }

    func processorResult() throws -> RemoteMessagingConfigProcessor.ProcessorResult {
        let jsonRemoteMessagingConfig = try decodeJson(fileName: "remote-messaging-config-example.json")
        let remoteMessagingConfigMatcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: MobileAppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
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
                percentileStore: RemoteMessagingPercentileUserDefaultsStore(keyValueStore: self.defaults),
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
