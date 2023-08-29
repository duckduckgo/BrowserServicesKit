//
//  SettingsProviderTests.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Common
import DDGSync
import GRDB
import Persistence
@testable import BrowserServicesKit
@testable import SyncDataProviders

final class SettingsProviderTests: SettingsProviderTestsBase {

    func testThatLastSyncTimestampIsNilByDefault() {
        XCTAssertNil(provider.lastSyncTimestamp)
    }

    func testThatLastSyncTimestampIsPersisted() throws {
        try provider.registerFeature(withState: .readyToSync)
        provider.lastSyncTimestamp = "12345"
        XCTAssertEqual(provider.lastSyncTimestamp, "12345")
    }

    func testThatPrepareForFirstSyncClearsLastSyncTimestampAndSetsModifiedAtForEmailSettings() throws {

        try emailManager.signIn(userEmail: "dax", token: "secret-token")

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        var settingsMetadata = try fetchAllSettingsMetadata(in: context)
        XCTAssertTrue(settingsMetadata.allSatisfy { $0.lastModified == nil })

        try provider.prepareForFirstSync()

        XCTAssertNil(provider.lastSyncTimestamp)

        settingsMetadata = try fetchAllSettingsMetadata(in: context)
        XCTAssertEqual(settingsMetadata.count, 1)
        XCTAssertTrue(settingsMetadata.allSatisfy { $0.lastModified != nil })
    }

    func testThatFetchChangedObjectsReturnsEmailSettingsWithNonNilModifiedAt() async throws {

        let otherEmailManager = EmailManager(storage: MockEmailManagerStorage())
        try otherEmailManager.signIn(userEmail: "dax", token: "secret-token")

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter).map(SyncableSettingAdapter.init)

        XCTAssertEqual(
            Set(changedObjects.compactMap(\.uuid)),
            Set([SettingsProvider.Setting.emailProtectionGeneration.key])
        )
    }

    func testWhenEmailProtectionIsDisabledThenFetchChangedObjectsContainsDeletedSyncable() async throws {

        let otherEmailManager = EmailManager(storage: MockEmailManagerStorage())
        try otherEmailManager.signOut()

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter).map(SyncableSettingAdapter.init)

        XCTAssertEqual(changedObjects.count, 1)

        let syncable = try XCTUnwrap(changedObjects.first)

        XCTAssertTrue(syncable.isDeleted)
        XCTAssertEqual(syncable.uuid, SettingsProvider.Setting.emailProtectionGeneration.key)
    }

    func testThatSentItemsAreProperlyCleanedUp() async throws {

        let otherEmailManager = EmailManager(storage: MockEmailManagerStorage())
        try otherEmailManager.signIn(userEmail: "dax", token: "secret-token")

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        try await provider.handleSyncResponse(sent: sent, received: [], clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = try fetchAllSettingsMetadata(in: context)
        XCTAssertTrue(settingsMetadata.isEmpty)
    }

    // MARK: - Initial Sync

    func testThatInitialSyncIntoEmptyDatabaseDoesNotCreateMetadataForReceivedObjects() async throws {

        let received: [Syncable] = [
            .emailProtection(userEmail: "abcd", token: "secret-token")
        ]

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = try fetchAllSettingsMetadata(in: context)
        XCTAssertTrue(settingsMetadata.isEmpty)
    }

    func testThatInitialSyncDeletesMetadataForDeduplicatedCredential() async throws {

        let date = Date()

        let emailManager = EmailManager(storage: MockEmailManagerStorage())
        try emailManager.signIn(userEmail: "dax", token: "secret-token")

        let received: [Syncable] = [
            .emailProtection(userEmail: "dax", token: try emailManager.getToken()!)
        ]

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: date.addingTimeInterval(1), serverTimestamp: "1234", crypter: crypter)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = try fetchAllSettingsMetadata(in: context)
        XCTAssertTrue(settingsMetadata.isEmpty)
    }

    func testWhenThereIsMergeConflictDuringInitialSyncThenSyncResponseHandlingIsRetried() async throws {
        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let emailManager = EmailManager(storage: emailManagerStorage)
        try emailManager.signIn(userEmail: "dax-local", token: "secret-token-local")

        let received: [Syncable] = [
            .emailProtection(userEmail: "dax", token: "secret-token")
        ]

        var willSaveCallCount = 0

        var emailProtectionModificationDate: Date?
        provider.willSaveContextAfterApplyingSyncResponse = {
            willSaveCallCount += 1
            if emailProtectionModificationDate != nil {
                return
            }
            try emailManager.signOut()
            context.performAndWait {
                emailProtectionModificationDate = SyncableSettingsMetadataUtils
                    .fetchSettingsMetadata(with: SettingsProvider.Setting.emailProtectionGeneration.key, in: context)?
                    .lastModified
            }
        }
        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        XCTAssertEqual(willSaveCallCount, 2)

        let settingsMetadata = try fetchAllSettingsMetadata(in: context)
        XCTAssertTrue(settingsMetadata.isEmpty)
        XCTAssertEqual(emailManagerStorage.mockUsername, "dax")
        XCTAssertEqual(emailManagerStorage.mockToken, "secret-token")
    }

    // MARK: - Regular Sync

    func testWhenEmailProtectionDeleteIsSentAndUpdateIsReceivedThenEmailProtectionIsNotDeleted() async throws {
        let emailManager = EmailManager(storage: emailManagerStorage)
        try emailManager.signIn(userEmail: "dax", token: "secret-token")
        try emailManager.signOut()

        let received: [Syncable] = [
            .emailProtection(userEmail: "dax", token: "secret-token2")
        ]

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = try fetchAllSettingsMetadata(in: context)
        XCTAssertTrue(settingsMetadata.isEmpty)
        XCTAssertEqual(emailManagerStorage.mockUsername, "dax")
        XCTAssertEqual(emailManagerStorage.mockToken, "secret-token2")
    }

    func testWhenEmailProtectionWasSentAndThenDisabledLocallyAndAnUpdateIsReceivedThenEmailProtectionIsDisabled() async throws {

        let emailManager = EmailManager(storage: emailManagerStorage)
        try emailManager.signIn(userEmail: "dax", token: "secret-token")

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        try emailManager.signOut()

        let received: [Syncable] = [
            .emailProtection(userEmail: "dax2", token: "secret-token2")
        ]

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date().advanced(by: -1), serverTimestamp: "1234", crypter: crypter)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = try fetchAllSettingsMetadata(in: context)
        XCTAssertEqual(settingsMetadata.count, 1)
        XCTAssertEqual(settingsMetadata.first?.key, SettingsProvider.Setting.emailProtectionGeneration.key)
        XCTAssertNotNil(settingsMetadata.first?.lastModified)
        XCTAssertNil(emailManagerStorage.mockUsername)
        XCTAssertNil(emailManagerStorage.mockToken)
    }

    func testWhenEmailProtectionWasEnabledLocallyAfterStartingSyncThenRemoteChangesAreDropped() async throws {

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        let emailManager = EmailManager(storage: emailManagerStorage)
        try emailManager.signIn(userEmail: "dax", token: "secret-token")

        let received: [Syncable] = [
            .emailProtection(userEmail: "dax2", token: "secret-token2")
        ]

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date().advanced(by: -1), serverTimestamp: "1234", crypter: crypter)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = try fetchAllSettingsMetadata(in: context)
        XCTAssertEqual(settingsMetadata.count, 1)
        XCTAssertEqual(settingsMetadata.first?.key, SettingsProvider.Setting.emailProtectionGeneration.key)
        XCTAssertNotNil(settingsMetadata.first?.lastModified)
        XCTAssertEqual(emailManagerStorage.mockUsername, "dax")
        XCTAssertEqual(emailManagerStorage.mockToken, "secret-token")
    }

    func testWhenEmailProtectionWasEnabledLocallyAfterStartingSyncThenRemoteDisableIsDropped() async throws {

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        let emailManager = EmailManager(storage: emailManagerStorage)
        try emailManager.signIn(userEmail: "dax", token: "secret-token")

        let received: [Syncable] = [
            .emailProtectionDeleted()
        ]

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date().advanced(by: -1), serverTimestamp: "1234", crypter: crypter)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = try fetchAllSettingsMetadata(in: context)
        XCTAssertEqual(settingsMetadata.count, 1)
        XCTAssertEqual(settingsMetadata.first?.key, SettingsProvider.Setting.emailProtectionGeneration.key)
        XCTAssertNotNil(settingsMetadata.first?.lastModified)
        XCTAssertEqual(emailManagerStorage.mockUsername, "dax")
        XCTAssertEqual(emailManagerStorage.mockToken, "secret-token")
    }

    func testWhenThereIsMergeConflictDuringRegularSyncThenSyncResponseHandlingIsRetried() async throws {
        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let emailManager = EmailManager(storage: emailManagerStorage)
        try emailManager.signIn(userEmail: "dax", token: "secret-token-local")

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        let received: [Syncable] = [
            .emailProtection(userEmail: "dax", token: "secret-token")
        ]

        var willSaveCallCount = 0

        var emailProtectionModificationDate: Date?
        provider.willSaveContextAfterApplyingSyncResponse = {
            willSaveCallCount += 1
            if emailProtectionModificationDate != nil {
                return
            }
            try emailManager.signOut()
            context.performAndWait {
                emailProtectionModificationDate = SyncableSettingsMetadataUtils
                    .fetchSettingsMetadata(with: SettingsProvider.Setting.emailProtectionGeneration.key, in: context)?
                    .lastModified
            }
        }
        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        XCTAssertEqual(willSaveCallCount, 2)

        let settingsMetadata = try fetchAllSettingsMetadata(in: context)
        XCTAssertEqual(settingsMetadata.count, 1)
        XCTAssertEqual(settingsMetadata.first?.key, SettingsProvider.Setting.emailProtectionGeneration.key)
        XCTAssertNotNil(settingsMetadata.first?.lastModified)
        XCTAssertNil(emailManagerStorage.mockUsername)
        XCTAssertNil(emailManagerStorage.mockToken)
    }
}
