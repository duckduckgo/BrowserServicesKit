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

        (dependencies.secureStore as! SecureStorageStub).theAccount = .mock
        dependencies.request.result = .init(data: "{\"bookmarks\":{\"last_modified\":\"1234\",\"entries\":[]}}".data(using: .utf8)!, response: .init())
    }

    override func tearDownWithError() throws {
        isInProgressCancellable?.cancel()
        isInProgressCancellable = nil

        try super.tearDownWithError()
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

    func setUpDataProviderCallbacks(for dataProvider: inout DataProvidingMock) {
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
        isInProgressCancellable = syncService.isInProgressPublisher.sink { isInProgress in
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
        var dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        setUpDataProviderCallbacks(for: &dataProvider)
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
        var dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        setUpDataProviderCallbacks(for: &dataProvider)
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

    func testWhenSyncOperationIsCancelledThenCurrentOperationReturnsEarlyAndOtherScheduledOperationsDoNotEmitSyncStarted() {
        var dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        setUpDataProviderCallbacks(for: &dataProvider)
        setUpExpectations(started: 2, fetch: 1, handleResponse: 1, finished: 2)

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded(isInternalUser: false)

        isInProgressCancellable = syncService.isInProgressPublisher.sink { [weak syncService] isInProgress in
            if isInProgress {
                self.recordedEvents.append(.started(self.taskID))
                self.syncStartedExpectation.fulfill()
                if self.taskID == 2 {
                    syncService?.scheduler.cancelSync()
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
        var dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        setUpDataProviderCallbacks(for: &dataProvider)

        setUpExpectations(started: 1, fetch: 1, handleResponse: 1, finished: 1)
        syncStartedExpectation.isInverted = true
        fetchExpectation.isInverted = true
        handleSyncResponseExpectation.isInverted = true
        syncFinishedExpectation.isInverted = true

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded(isInternalUser: false)
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.cancelSync()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 0.1)

        XCTAssertEqual(recordedEvents, [])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallArgs, [])
    }

    func testWhenSyncQueueIsResumedThenScheduledOperationStarts() {
        var dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        setUpDataProviderCallbacks(for: &dataProvider)

        setUpExpectations(started: 1, fetch: 1, handleResponse: 1, finished: 1)

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded(isInternalUser: false)
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.cancelSync()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.resumeSync()

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
}
