//
//  SettingsRegularSyncResponseHandlerTests.swift
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

final class SettingsRegularSyncResponseHandlerTests: SettingsProviderTestsBase {

    func testThatEmailProtectionEnabledStateIsApplied() async throws {
        let received: [Syncable] = [
            .emailProtection(userEmail: "dax", token: "secret-token")
        ]

        try await handleSyncResponse(received: received)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = try fetchAllSettingsMetadata(in: context)
        XCTAssertTrue(settingsMetadata.isEmpty)
        XCTAssertEqual(emailManagerStorage.mockUsername, "dax")
        XCTAssertEqual(emailManagerStorage.mockToken, "secret-token")
    }

    func testThatEmailProtectionDisabledStateIsApplied() async throws {
        let emailManager = EmailManager(storage: emailManagerStorage)
        try emailManager.signIn(userEmail: "dax", token: "secret-token")

        let received: [Syncable] = [
            .emailProtectionDeleted()
        ]

        try await handleSyncResponse(received: received)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = try fetchAllSettingsMetadata(in: context)
        XCTAssertTrue(settingsMetadata.isEmpty)
        XCTAssertNil(emailManagerStorage.mockUsername)
        XCTAssertNil(emailManagerStorage.mockToken)
    }

    func testThatEmailProtectionIsEnabledLocallyAndRemotelyThenRemoteStateIsApplied() async throws {
        let emailManager = EmailManager(storage: emailManagerStorage)
        try emailManager.signIn(userEmail: "dax-local", token: "secret-token-local")

        let received: [Syncable] = [
            .emailProtection(userEmail: "dax-remote", token: "secret-token-remote")
        ]

        try await handleSyncResponse(received: received)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = try fetchAllSettingsMetadata(in: context)
        XCTAssertTrue(settingsMetadata.isEmpty)
        XCTAssertEqual(emailManagerStorage.mockUsername, "dax-remote")
        XCTAssertEqual(emailManagerStorage.mockToken, "secret-token-remote")
    }
}
