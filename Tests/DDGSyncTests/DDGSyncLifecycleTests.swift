//
//  DDGSyncLifecycleTests.swift
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

import Combine
import Common
import XCTest
@testable import DDGSync

final class DDGSyncLifecycleTests: XCTestCase {

    var dataProvidersSource: MockDataProvidersSource!
    var dependencies: MockSyncDependencies!

    var mockKeyValueStore: MockKeyValueStore {
        dependencies.keyValueStore as! MockKeyValueStore
    }

    var secureStorageStub: SecureStorageStub {
        dependencies.secureStore as! SecureStorageStub
    }

    var mockErrorHandler: MockErrorHandler {
        dependencies.errorEvents as! MockErrorHandler
    }

    override func setUp() {
        super.setUp()

        dataProvidersSource = MockDataProvidersSource()
        dependencies = MockSyncDependencies()
    }

    func testWhenInitializingAndOffThenStateIsInactive() {
        secureStorageStub.theAccount = nil
        mockKeyValueStore.isSyncEnabled = false

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        XCTAssertEqual(syncService.authState, .initializing)
        syncService.initializeIfNeeded()
        XCTAssertEqual(syncService.authState, .inactive)
        XCTAssertEqual(mockErrorHandler.handledErrors, [])
    }

    func testWhenInitializingAndOnThenStateIsActive() {
        secureStorageStub.theAccount = .mock

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        XCTAssertEqual(syncService.authState, .initializing)
        syncService.initializeIfNeeded()
        XCTAssertEqual(syncService.authState, .active)
        XCTAssertEqual(mockErrorHandler.handledErrors, [])
    }

    func testWhenInitializingAndAfterReinstallThenStateIsInactive() {
        secureStorageStub.theAccount = .mock
        mockKeyValueStore.isSyncEnabled = nil

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        XCTAssertEqual(syncService.authState, .initializing)
        syncService.initializeIfNeeded()
        XCTAssertEqual(syncService.authState, .inactive)
        XCTAssertNil(secureStorageStub.theAccount)
        XCTAssertEqual(mockErrorHandler.handledErrors, [])
    }

    func testWhenInitializingAndCannotReadAccountThenErrorIsReportedAndInitializationIsPostponed() {
        let expectedError = SyncError.failedToReadSecureStore(status: 0)
        secureStorageStub.theAccount = .mock
        secureStorageStub.mockReadError = expectedError

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        XCTAssertEqual(syncService.authState, .initializing)
        syncService.initializeIfNeeded()
        XCTAssertEqual(syncService.authState, .initializing)
        XCTAssertEqual(mockErrorHandler.handledErrors, [.failedToLoadAccount])
    }

    func testWhenInitializingAndCannotSaveAccountThenErrorIsReported() {
        let expectedError = SyncError.failedToWriteSecureStore(status: 0)
        secureStorageStub.theAccount = .mock
        secureStorageStub.mockWriteError = expectedError

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        XCTAssertEqual(syncService.authState, .initializing)
        syncService.initializeIfNeeded()
        // Account has been red, so it is active
        XCTAssertEqual(syncService.authState, .active)
        XCTAssertEqual(mockErrorHandler.handledErrors, [.failedToSetupEngine])
    }

}
