//
//  WorkerTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
@testable import DDGSync

class HTTPRequestingMock: HTTPRequesting {
    var executeCallCount = 0
    var error: SyncError?
    var result: HTTPResult = .init(data: Data(), response: HTTPURLResponse())

    func execute() async throws -> HTTPResult {
        executeCallCount += 1
        if let error {
            throw error
        }
        return result
    }
}

class RemoteAPIRequestCreatingMock: RemoteAPIRequestCreating {
    var createRequestCallCount = 0
    var createRequestCallArgs: [CreateRequestCallArgs] = []
    var request: HTTPRequesting = HTTPRequestingMock()
    struct CreateRequestCallArgs {
        let url: URL
        let method: HTTPRequestMethod
        let headers: [String: String]
        let parameters: [String: String] 
        let body: Data?
        let contentType: String?
    }

    func createRequest(url: URL, method: HTTPRequestMethod, headers: [String: String], parameters: [String: String], body: Data?, contentType: String?) -> HTTPRequesting {
        createRequestCallCount += 1
        createRequestCallArgs.append(CreateRequestCallArgs(url: url, method: method, headers: headers, parameters: parameters, body: body, contentType: contentType))
        return request
    }
}

struct DataProvidingMock: DataProviding {

    var feature: Feature
    var lastSyncTimestamp: String?
    var changes: (String?) async throws -> [Syncable] = { _ in return [] }
    
    func changes(since timestamp: String?) async throws -> [Syncable] {
        return try await changes(timestamp)
    }
}

class WorkerTests: XCTestCase {
    var apiMock: RemoteAPIRequestCreatingMock!
    var request: HTTPRequestingMock!
    var endpoints: Endpoints!

    override func setUpWithError() throws {
        try super.setUpWithError()

        apiMock = RemoteAPIRequestCreatingMock()
        request = HTTPRequestingMock()
        request.error = .noResponseBody
        apiMock.request = request
        endpoints = Endpoints(baseUrl: URL(string: "https://example.com")!)
    }

    func testWhenThereAreNoChangesThenGetRequestIsFired() async throws {
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        let worker = Worker(dataProviders: [dataProvider], api: apiMock, endpoints: endpoints)

        await assertThrowsError(SyncError.noResponseBody) {
            try await worker.sync()
        }
        XCTAssertEqual(apiMock.createRequestCallCount, 1)
        XCTAssertEqual(apiMock.createRequestCallArgs[0].method, .GET)
    }

    func testWhenThereAreChangesThenPatchRequestIsFired() async throws {
        var dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        dataProvider.changes = { _ in
            return [Syncable(jsonObject: [:])]
        }
        let worker = Worker(dataProviders: [dataProvider], api: apiMock, endpoints: endpoints)

        await assertThrowsError(SyncError.noResponseBody) {
            try await worker.sync()
        }
        XCTAssertEqual(apiMock.createRequestCallCount, 1)
        XCTAssertEqual(apiMock.createRequestCallArgs[0].method, .PATCH)
    }
}
