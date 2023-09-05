//
//  DDGSyncTests.swift
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

enum SyncOperationEvent: Equatable {
    case started(_ taskID: Int)
    case fetch(_ taskID: Int)
    case handleResponse(_ taskID: Int)
    case finished(_ taskID: Int)
}

final class DDGSyncTests: XCTestCase {
    var dataProvidersSource: MockDataProvidersSource!
    var dependencies: MockSyncDepenencies!

    var syncStartedExpectation: XCTestExpectation!
    var fetchExpectation: XCTestExpectation!
    var handleSyncResponseExpectation: XCTestExpectation!
    var syncFinishedExpectation: XCTestExpectation!
    var isInProgressCancellable: AnyCancellable?
    var recordedEvents: [SyncOperationEvent] = []
    var taskID = 1

    override func setUpWithError() throws {
        try super.setUpWithError()

        recordedEvents = []
        taskID = 1

        dataProvidersSource = MockDataProvidersSource()
        dependencies = MockSyncDepenencies()
        (dependencies.api as! RemoteAPIRequestCreatingMock).fakeRequests = [
            URL(string: "https://dev.null/sync/credentials")!: HTTPRequestingMock(result: .init(data: "{\"credentials\":{\"last_modified\":\"1234\",\"entries\":[]}}".data(using: .utf8)!, response: .init())),
            URL(string: "https://dev.null/sync/bookmarks")!: HTTPRequestingMock(result: .init(data: "{\"bookmarks\":{\"last_modified\":\"1234\",\"entries\":[]}}".data(using: .utf8)!, response: .init())),
            URL(string: "https://dev.null/sync/data")!: HTTPRequestingMock(result: .init(data: "{\"bookmarks\":{\"last_modified\":\"1234\",\"entries\":[]},\"credentials\":{\"last_modified\":\"1234\",\"entries\":[]}}".data(using: .utf8)!, response: .init()))
        ]

        (dependencies.secureStore as! SecureStorageStub).theAccount = .mock
    }

    override func tearDownWithError() throws {
        isInProgressCancellable?.cancel()
        isInProgressCancellable = nil

        try super.tearDownWithError()
    }

    func testSyncErrorCodes() {
        print((SyncError.noToken as NSError).code)
        print((SyncError.failedToMigrate as NSError).code)
        print((SyncError.failedToLoadAccount as NSError).code)
        print((SyncError.failedToSetupEngine as NSError).code)
        print((SyncError.failedToCreateAccountKeys("") as NSError).code)
        print((SyncError.accountNotFound as NSError).code)
        print((SyncError.accountAlreadyExists as NSError).code)
        print((SyncError.invalidRecoveryKey as NSError).code)
        print((SyncError.noFeaturesSpecified as NSError).code)
        print((SyncError.noResponseBody as NSError).code)
        print((SyncError.unexpectedStatusCode(1) as NSError).code)
        print((SyncError.unexpectedResponseBody as NSError).code)
        print((SyncError.unableToEncodeRequestBody("") as NSError).code)
        print((SyncError.unableToDecodeResponse("") as NSError).code)
        print((SyncError.invalidDataInResponse("") as NSError).code)
        print((SyncError.accountRemoved as NSError).code)
        print((SyncError.failedToEncryptValue("") as NSError).code)
        print((SyncError.failedToDecryptValue("") as NSError).code)
        print((SyncError.failedToPrepareForConnect("") as NSError).code)
        print((SyncError.failedToOpenSealedBox("") as NSError).code)
        print((SyncError.failedToSealData("") as NSError).code)
        print((SyncError.failedToWriteSecureStore(status: 1) as NSError).code)
        print((SyncError.failedToReadSecureStore(status: 1) as NSError).code)
        print((SyncError.failedToRemoveSecureStore(status: 1) as NSError).code)
        print((SyncError.credentialsMetadataMissingBeforeFirstSync as NSError).code)
        print((SyncError.receivedCredentialsWithoutUUID as NSError).code)
    }

    // MARK: - Setup

    func setUpExpectations(started syncStartedExpectedCount: Int, fetch fetchExpectedCount: Int, handleResponse handleSyncResponseExpectedCount: Int, finished syncFinishedExpectedCount: Int) {
        syncStartedExpectation = expectation(description: "syncStarted")
        fetchExpectation = expectation(description: "fetch")
        handleSyncResponseExpectation = expectation(description: "handleSyncResponse")
        syncFinishedExpectation = expectation(description: "syncFinished")

        syncStartedExpectation.expectedFulfillmentCount = syncStartedExpectedCount
        fetchExpectation.expectedFulfillmentCount = fetchExpectedCount
        handleSyncResponseExpectation.expectedFulfillmentCount = handleSyncResponseExpectedCount
        syncFinishedExpectation.expectedFulfillmentCount = syncFinishedExpectedCount
    }

    func setUpDataProviderCallbacks(for dataProvider: DataProvidingMock) {
        dataProvider._fetchChangedObjects = { _ in
            let syncables = [Syncable(jsonObject: ["taskNumber": self.taskID])]
            self.recordedEvents.append(.fetch(self.taskID))
            self.fetchExpectation.fulfill()
            return syncables
        }
        dataProvider.handleSyncResponse = { sent, _, _, _, _ in
            let taskID = sent[0].payload["taskNumber"] as! Int
            self.recordedEvents.append(.handleResponse(taskID))
            self.handleSyncResponseExpectation.fulfill()
        }
    }

    func bindInProgressPublisher(for syncService: DDGSyncing) {
        isInProgressCancellable = syncService.isSyncInProgressPublisher.sink { isInProgress in
            if isInProgress {
                self.recordedEvents.append(.started(self.taskID))
                self.syncStartedExpectation.fulfill()
            } else {
                self.recordedEvents.append(.finished(self.taskID))
                self.syncFinishedExpectation.fulfill()
                self.taskID += 1
            }
        }
    }

    // MARK: - Tests

    func testThatRegularSyncOperationsAreSerialized() {
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        dataProvider.lastSyncTimestamp = "1234"
        setUpDataProviderCallbacks(for: dataProvider)
        setUpExpectations(started: 3, fetch: 3, handleResponse: 3, finished: 3)

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded(isInternalUser: false)
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 1)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .handleResponse(1),
            .finished(1),
            .started(2),
            .fetch(2),
            .handleResponse(2),
            .finished(2),
            .started(3),
            .fetch(3),
            .handleResponse(3),
            .finished(3)
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallCount, 3)
        XCTAssertEqual(api.createRequestCallArgs.map(\.method), [.PATCH, .PATCH, .PATCH])
    }

    func testThatFirstSyncAndRegularSyncOperationsAreSerialized() {
        (dependencies.secureStore as! SecureStorageStub).theAccount = .mock.updatingState(.addingNewDevice)
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        setUpDataProviderCallbacks(for: dataProvider)
        setUpExpectations(started: 3, fetch: 3, handleResponse: 3, finished: 3)

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded(isInternalUser: false)
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 1)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .handleResponse(1),
            .finished(1),
            .started(2),
            .fetch(2),
            .handleResponse(2),
            .finished(2),
            .started(3),
            .fetch(3),
            .handleResponse(3),
            .finished(3)
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallCount, 4)
        XCTAssertEqual(api.createRequestCallArgs.map(\.method), [.GET, .PATCH, .PATCH, .PATCH])
    }

    func testWhenNewSyncAccountIsCreatedWithMultipleModelsThenInitialFetchDoesNotHappen() throws {
        (dependencies.secureStore as! SecureStorageStub).theAccount = .mock.updatingState(.active)
        let bookmarksDataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        bookmarksDataProvider._fetchChangedObjects = { _ in
            [.init(jsonObject: ["id": UUID().uuidString])]
        }

        let credentialsDataProvider = DataProvidingMock(feature: .init(name: "credentials"))
        credentialsDataProvider._fetchChangedObjects = { _ in
            [.init(jsonObject: ["id": UUID().uuidString])]
        }
        setUpDataProviderCallbacks(for: credentialsDataProvider)
        setUpExpectations(started: 1, fetch: 1, handleResponse: 1, finished: 1)

        dataProvidersSource.dataProviders = [bookmarksDataProvider, credentialsDataProvider]
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded(isInternalUser: false)
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 1)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .handleResponse(1),
            .finished(1)
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallCount, 2)
        XCTAssertEqual(api.createRequestCallArgs.map(\.method), [.PATCH, .PATCH])
    }

    func testWhenDeviceIsAddedToExistingSyncAccountWithMultipleModelsThenInitialFetchHappens() throws {
        (dependencies.secureStore as! SecureStorageStub).theAccount = .mock.updatingState(.addingNewDevice)
        let bookmarksDataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        bookmarksDataProvider._fetchChangedObjects = { _ in
            [.init(jsonObject: ["id": UUID().uuidString])]
        }

        let credentialsDataProvider = DataProvidingMock(feature: .init(name: "credentials"))
        credentialsDataProvider._fetchChangedObjects = { _ in
            [.init(jsonObject: ["id": UUID().uuidString])]
        }
        setUpDataProviderCallbacks(for: credentialsDataProvider)
        setUpExpectations(started: 1, fetch: 1, handleResponse: 1, finished: 1)

        dataProvidersSource.dataProviders = [bookmarksDataProvider, credentialsDataProvider]
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded(isInternalUser: false)
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 1)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .handleResponse(1),
            .finished(1)
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallCount, 4)
        XCTAssertEqual(api.createRequestCallArgs.map(\.method), [.GET, .GET, .PATCH, .PATCH])
    }

    /// Test initial fetch for newly added models.
    ///
    /// Start with:
    /// * Sync in active state
    /// * bookmarks provider that has been synced
    /// * credentials provider that hasn't been synced
    ///
    /// Request sync twice and test that:
    /// * the first sync operation calls 3 requests: initial for credentials, and regular for bookmarks and credentials
    /// * the second sync operation calls 2 request: regular sync for bookmarks and credentials
    func testThatWhenNewModelIsAddedThenItPerformsInitialFetch() throws {
        (dependencies.secureStore as! SecureStorageStub).theAccount = .mock.updatingState(.active)
        let bookmarksDataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        try bookmarksDataProvider.registerFeature(withState: .readyToSync)
        bookmarksDataProvider.lastSyncTimestamp = "1234"
        bookmarksDataProvider._fetchChangedObjects = { _ in
            [.init(jsonObject: ["id": UUID().uuidString])]
        }

        let credentialsDataProvider = DataProvidingMock(feature: .init(name: "credentials"))
        credentialsDataProvider._fetchChangedObjects = { _ in
            [.init(jsonObject: ["id": UUID().uuidString])]
        }
        setUpDataProviderCallbacks(for: credentialsDataProvider)
        setUpExpectations(started: 2, fetch: 2, handleResponse: 2, finished: 2)

        dataProvidersSource.dataProviders = [bookmarksDataProvider, credentialsDataProvider]
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded(isInternalUser: false)
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 1)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .handleResponse(1),
            .finished(1),
            .started(2),
            .fetch(2),
            .handleResponse(2),
            .finished(2)
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallCount, 5)
        XCTAssertEqual(api.createRequestCallArgs.map(\.method), [.GET, .PATCH, .PATCH, .PATCH, .PATCH])
        XCTAssertEqual(api.createRequestCallArgs[0].url.lastPathComponent, "credentials")
    }

    func testWhenSyncOperationIsCancelledThenCurrentOperationReturnsEarlyAndOtherScheduledOperationsDoNotEmitSyncStarted() {
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        dataProvider.lastSyncTimestamp = "1234"
        setUpDataProviderCallbacks(for: dataProvider)
        setUpExpectations(started: 2, fetch: 1, handleResponse: 1, finished: 2)

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded(isInternalUser: false)

        isInProgressCancellable = syncService.isSyncInProgressPublisher.sink { [weak syncService] isInProgress in
            if isInProgress {
                self.recordedEvents.append(.started(self.taskID))
                self.syncStartedExpectation.fulfill()
                if self.taskID == 2 {
                    syncService?.scheduler.cancelSyncAndSuspendSyncQueue()
                }
            } else {
                self.recordedEvents.append(.finished(self.taskID))
                self.syncFinishedExpectation.fulfill()
                self.taskID += 1
            }
        }

        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 1)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .handleResponse(1),
            .finished(1),
            .started(2),
            .finished(2)
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallArgs.map(\.method), [.PATCH])
    }

    func testWhenSyncQueueIsSuspendedThenNewOperationsDoNotStart() {
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        setUpDataProviderCallbacks(for: dataProvider)

        setUpExpectations(started: 1, fetch: 1, handleResponse: 1, finished: 1)
        syncStartedExpectation.isInverted = true
        fetchExpectation.isInverted = true
        handleSyncResponseExpectation.isInverted = true
        syncFinishedExpectation.isInverted = true

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded(isInternalUser: false)
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.cancelSyncAndSuspendSyncQueue()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 0.1)

        XCTAssertEqual(recordedEvents, [])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallArgs, [])
    }

    func testWhenSyncQueueIsResumedThenScheduledOperationStarts() {
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        dataProvider.lastSyncTimestamp = "1234"
        setUpDataProviderCallbacks(for: dataProvider)

        setUpExpectations(started: 1, fetch: 1, handleResponse: 1, finished: 1)

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded(isInternalUser: false)
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.cancelSyncAndSuspendSyncQueue()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.resumeSyncQueue()

        waitForExpectations(timeout: 0.1)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .handleResponse(1),
            .finished(1)
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallArgs.map(\.method), [.PATCH])
    }

    func testWhenSyncGetsDisabledBeforeStartingOperationThenOperationReturnsEarly() throws {
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        setUpDataProviderCallbacks(for: dataProvider)
        setUpExpectations(started: 1, fetch: 1, handleResponse: 1, finished: 1)
        fetchExpectation.isInverted = true
        handleSyncResponseExpectation.isInverted = true

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded(isInternalUser: false)
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.requestSyncImmediately()
        try dependencies.secureStore.removeAccount()

        waitForExpectations(timeout: 1)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .finished(1),
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertTrue(api.createRequestCallArgs.isEmpty)
    }
}
