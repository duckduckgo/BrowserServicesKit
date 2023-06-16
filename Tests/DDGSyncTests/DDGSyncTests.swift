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

private enum SyncOperationEvent: Equatable {
    case started(_ taskID: Int)
    case fetch(_ taskID: Int)
    case handleResponse(_ taskID: Int)
    case finished(_ taskID: Int)
}

final class DDGSyncTests: XCTestCase {
    var dataProvidersSource: MockDataProvidersSource!
    var dependencies: MockSyncDepenencies!

    override func setUpWithError() throws {
        try super.setUpWithError()

        dataProvidersSource = MockDataProvidersSource()
        dependencies = MockSyncDepenencies()

        (dependencies.secureStore as! SecureStorageStub).theAccount = .mock
        dependencies.request.result = .init(data: "{\"bookmarks\":{\"last_modified\":\"1234\",\"entries\":[]}}".data(using: .utf8)!, response: .init())
    }

    func testThatRegularSyncOperationsAreSerialized() {
        var dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))

        var events: [SyncOperationEvent] = []
        var taskID = 1

        let syncStartedExpectation = expectation(description: "syncStarted")
        let fetchExpectation = expectation(description: "fetch")
        let handleSyncResponseExpectation = expectation(description: "handleSyncResponse")
        let syncFinishedExpectation = expectation(description: "syncFinished")

        syncStartedExpectation.expectedFulfillmentCount = 3
        fetchExpectation.expectedFulfillmentCount = 3
        handleSyncResponseExpectation.expectedFulfillmentCount = 3
        syncFinishedExpectation.expectedFulfillmentCount = 3

        dataProvider._fetchChangedObjects = { _ in
            let syncables = [Syncable(jsonObject: ["taskNumber": taskID])]
            events.append(.fetch(taskID))
            fetchExpectation.fulfill()
            return syncables
        }
        dataProvider.handleSyncResponse = { sent, _, _, _, _ in
            let taskID = sent[0].payload["taskNumber"] as! Int
            events.append(.handleResponse(taskID))
            handleSyncResponseExpectation.fulfill()
        }

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        let isInProgressCancellable = syncService.isInProgressPublisher.sink { isInProgress in
            if isInProgress {
                events.append(.started(taskID))
                syncStartedExpectation.fulfill()
            } else {
                events.append(.finished(taskID))
                syncFinishedExpectation.fulfill()
                taskID += 1
            }
        }

        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 1)
        isInProgressCancellable.cancel()

        XCTAssertEqual(events, [
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
    }

    func testThatFirstSyncAndRegularSyncOperationsAreSerialized() {
        (dependencies.secureStore as! SecureStorageStub).theAccount = .mock.updatingState(.addingNewDevice)
        var dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))

        var events: [SyncOperationEvent] = []
        var taskID = 1

        let syncStartedExpectation = expectation(description: "syncStarted")
        let fetchExpectation = expectation(description: "fetch")
        let handleSyncResponseExpectation = expectation(description: "handleSyncResponse")
        let syncFinishedExpectation = expectation(description: "syncFinished")

        syncStartedExpectation.assertForOverFulfill = false
        syncFinishedExpectation.assertForOverFulfill = false
        syncStartedExpectation.expectedFulfillmentCount = 4
        fetchExpectation.expectedFulfillmentCount = 3
        handleSyncResponseExpectation.expectedFulfillmentCount = 3
        syncFinishedExpectation.expectedFulfillmentCount = 4

        dataProvider._fetchChangedObjects = { _ in
            let syncables = [Syncable(jsonObject: ["taskNumber": taskID])]
            events.append(.fetch(taskID))
            fetchExpectation.fulfill()
            return syncables
        }
        dataProvider.handleSyncResponse = { sent, _, _, _, _ in
            let taskID = sent[0].payload["taskNumber"] as! Int
            events.append(.handleResponse(taskID))
            handleSyncResponseExpectation.fulfill()
        }

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        let isInProgressCancellable = syncService.isInProgressPublisher.sink { isInProgress in
            if isInProgress {
                events.append(.started(taskID))
                syncStartedExpectation.fulfill()
            } else {
                events.append(.finished(taskID))
                syncFinishedExpectation.fulfill()
                taskID += 1
            }
        }

        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 1)
        isInProgressCancellable.cancel()

        XCTAssertEqual(events, [
            .started(1),
            .finished(1),
            .started(2),
            .fetch(2),
            .handleResponse(2),
            .finished(2),
            .started(3),
            .fetch(3),
            .handleResponse(3),
            .finished(3),
            .started(4),
            .fetch(4),
            .handleResponse(4),
            .finished(4)
        ])
    }
}
