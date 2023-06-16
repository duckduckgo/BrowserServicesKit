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

enum Event: Equatable {
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
    }

    func testThatRegularSyncOperationsAreSerialized() {
        var dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        dependencies.request.result = .init(data: "{\"bookmarks\":{\"last_modified\":\"1234\",\"entries\":[]}}".data(using: .utf8)!, response: .init())

        var events: [Event] = []
        var taskID = 1

        let expectation = expectation(description: "handleSyncResponse")
        expectation.expectedFulfillmentCount = 3

        dataProvider._fetchChangedObjects = { _ in
            let syncables = [Syncable(jsonObject: ["taskNumber": taskID])]
            events.append(.fetch(taskID))
            return syncables
        }
        dataProvider.handleSyncResponse = { sent, _, _, _, _ in
            let taskID = sent[0].payload["taskNumber"] as! Int
            events.append(.handleResponse(taskID))
            expectation.fulfill()
        }

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        var isInProgressCancellable: AnyCancellable? = syncService.isInProgressPublisher.sink { isInProgress in
            if isInProgress {
                events.append(.started(taskID))
            } else {
                events.append(.finished(taskID))
                taskID += 1
            }
        }

        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 1)
        isInProgressCancellable?.cancel()
        isInProgressCancellable = nil

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
        dependencies.request.result = .init(data: "{\"bookmarks\":{\"last_modified\":\"1234\",\"entries\":[]}}".data(using: .utf8)!, response: .init())

        enum Event: Equatable {
            case fetch(_ taskID: Int)
            case handleResponse(_ taskID: Int)
        }

        var events: [Event] = []
        var taskID = 1

        let fetchExpectation = expectation(description: "fetch")
        fetchExpectation.expectedFulfillmentCount = 3
        let handleSyncResponseExpectation = expectation(description: "handleSyncResponse")
        handleSyncResponseExpectation.expectedFulfillmentCount = 3

        dataProvider._fetchChangedObjects = { _ in
            let syncables = [Syncable(jsonObject: ["taskNumber": taskID])]
            events.append(.fetch(taskID))
            taskID += 1
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
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 1)

        XCTAssertEqual(events, [
            .fetch(1),
            .handleResponse(1),
            .fetch(2),
            .handleResponse(2),
            .fetch(3),
            .handleResponse(3)
        ])
    }
}
