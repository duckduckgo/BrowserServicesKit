//
//  EngineTests.swift
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
    private let lock = NSLock()

    struct CreateRequestCallArgs {
        let url: URL
        let method: HTTPRequestMethod
        let headers: [String: String]
        let parameters: [String: String] 
        let body: Data?
        let contentType: String?
    }

    func createRequest(url: URL, method: HTTPRequestMethod, headers: [String: String], parameters: [String: String], body: Data?, contentType: String?) -> HTTPRequesting {
        lock.lock()
        defer { lock.unlock() }
        createRequestCallCount += 1
        createRequestCallArgs.append(CreateRequestCallArgs(url: url, method: method, headers: headers, parameters: parameters, body: body, contentType: contentType))
        return request
    }
}

struct CryptingMock: Crypting {

    var _encryptAndBase64Encode: (String) throws -> String = { "encrypted_\($0)" }
    var _base64DecodeAndDecrypt: (String) throws -> String = { $0.dropping(prefix: "encrypted_") }

    func encryptAndBase64Encode(_ value: String) throws -> String {
        try _encryptAndBase64Encode(value)
    }

    func base64DecodeAndDecrypt(_ value: String) throws -> String {
        try _base64DecodeAndDecrypt(value)
    }
}

struct DataProvidingMock: DataProviding {

    var feature: Feature
    var lastSyncTimestamp: String?
    var _prepareForFirstSync: () -> Void = {}
    var _fetchChangedObjects: (Crypting) async throws -> [Syncable] = { _ in return [] }
    var handleInitialSyncResponse: ([Syncable], Date, String?, Crypting) async throws -> Void = { _,_,_,_ in }
    var handleSyncResponse: ([Syncable], [Syncable], Date, String?, Crypting) async throws -> Void = { _,_,_,_,_ in }
    var handleSyncError: (Error) -> Void = { _ in }

    func prepareForFirstSync() {
        _prepareForFirstSync()
    }

    func fetchChangedObjects(encryptedUsing crypter: Crypting) async throws -> [Syncable] {
        try await _fetchChangedObjects(crypter)
    }

    func handleInitialSyncResponse(received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws {
        try await handleInitialSyncResponse(received, clientTimestamp, serverTimestamp, crypter)
    }

    func handleSyncResponse(sent: [Syncable], received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws {
        try await handleSyncResponse(sent, received, clientTimestamp, serverTimestamp, crypter)
    }

    func handleSyncError(error: Error) {
        handleSyncError(error)
    }
}

class EngineTests: XCTestCase {
    var apiMock: RemoteAPIRequestCreatingMock!
    var request: HTTPRequestingMock!
    var endpoints: Endpoints!
    var storage: SecureStorageStub!
    var crypter: CryptingMock!
    var requestMaker: SyncRequestMaking!

    override func setUpWithError() throws {
        try super.setUpWithError()

        apiMock = RemoteAPIRequestCreatingMock()
        request = HTTPRequestingMock()
        apiMock.request = request
        endpoints = Endpoints(baseUrl: URL(string: "https://example.com")!)
        storage = SecureStorageStub()
        crypter = CryptingMock()
        try storage.persistAccount(
            SyncAccount(
                deviceId: "deviceId",
                deviceName: "deviceName",
                deviceType: "deviceType",
                userId: "userId",
                primaryKey: "primaryKey".data(using: .utf8)!,
                secretKey: "secretKey".data(using: .utf8)!,
                token: "token",
                state: .active
            )
        )

        requestMaker = SyncRequestMaker(storage: storage, api: apiMock, endpoints: endpoints)
    }

    func testWhenThereAreNoChangesThenGetRequestIsFired() async throws {
        let feature = Feature(name: "bookmarks")
        let dataProvider = DataProvidingMock(feature: feature)
        let engine = Engine(dataProviders: [dataProvider], storage: storage, crypter: crypter, api: apiMock, endpoints: endpoints)

        request.error = .noResponseBody
        await assertThrowsAnyError({
            try await engine.sync(fetchOnly: false)
        }, errorHandler: { error in
            guard let syncOperationError = error as? SyncOperationError, let featureError = syncOperationError.perFeatureErrors[feature] as? SyncError else  {
                XCTFail("Unexpected error thrown: \(error)")
                return
            }
            XCTAssertEqual(featureError, .noResponseBody)
        })
        XCTAssertEqual(apiMock.createRequestCallCount, 1)
        XCTAssertEqual(apiMock.createRequestCallArgs[0].method, .GET)
    }

    func testWhenThereAreChangesThenPatchRequestIsFired() async throws {
        let feature = Feature(name: "bookmarks")
        var dataProvider = DataProvidingMock(feature: feature)
        dataProvider.lastSyncTimestamp = "1234"
        dataProvider._fetchChangedObjects = { _ in
            [Syncable(jsonObject: [:])]
        }
        let engine = Engine(dataProviders: [dataProvider], storage: storage, crypter: crypter, api: apiMock, endpoints: endpoints)

        request.error = .noResponseBody
        await assertThrowsAnyError({
            try await engine.sync(fetchOnly: false)
        }, errorHandler: { error in
            guard let syncOperationError = error as? SyncOperationError, let featureError = syncOperationError.perFeatureErrors[feature] as? SyncError else  {
                XCTFail("Unexpected error thrown: \(error)")
                return
            }
            XCTAssertEqual(featureError, .noResponseBody)
        })
        XCTAssertEqual(apiMock.createRequestCallCount, 1)
        XCTAssertEqual(apiMock.createRequestCallArgs[0].method, .PATCH)
    }

    func testThatForMultipleDataProvidersRequestsSeparateRequstsAreSentConcurrently() async throws {
        var dataProvider1 = DataProvidingMock(feature: .init(name: "bookmarks"))
        dataProvider1.lastSyncTimestamp = "1234"
        dataProvider1._fetchChangedObjects = { _ in
            [
                Syncable(jsonObject: ["id": "1", "name": "bookmark1", "url": "https://example.com"]),
                Syncable(jsonObject: ["id": "2", "name": "bookmark2", "url": "https://example.com"]),
            ]
        }
        var dataProvider2 = DataProvidingMock(feature: .init(name: "settings"))
        dataProvider2.lastSyncTimestamp = "5678"
        dataProvider2._fetchChangedObjects = { _ in
            [
                Syncable(jsonObject: ["key": "setting-a", "value": "value-a"]),
                Syncable(jsonObject: ["key": "setting-b", "value": "value-b"])
            ]
        }
        var dataProvider3 = DataProvidingMock(feature: .init(name: "autofill"))
        dataProvider3.lastSyncTimestamp = "9012"
        dataProvider3._fetchChangedObjects = { _ in
            [
                Syncable(jsonObject: ["id": "1", "login": "login1", "password": "password1", "url": "https://example.com"]),
                Syncable(jsonObject: ["id": "2", "login": "login2", "password": "password2", "url": "https://example.com"])
            ]
        }

        let engine = Engine(dataProviders: [dataProvider1, dataProvider2, dataProvider3], storage: storage, crypter: crypter, api: apiMock, endpoints: endpoints)

        request.error = .noResponseBody
        await assertThrowsAnyError {
            try await engine.sync(fetchOnly: false)
        }

        let bookmarks = BookmarksPayload(
            bookmarks: .init(
                updates: [
                    .init(id: "1", name: "bookmark1", url: "https://example.com"),
                    .init(id: "2", name: "bookmark2", url: "https://example.com")
                ],
                modifiedSince: "1234"
            )
        )
        let settings = SettingsPayload(
            settings: .init(
                updates: [
                    .init(key: "setting-a", value: "value-a"),
                    .init(key: "setting-b", value: "value-b")
                ],
                modifiedSince: "5678"
            )
        )
        let autofill = AutofillPayload(
            autofill: .init(
                updates: [
                    .init(id: "1", login: "login1", password: "password1", url: "https://example.com"),
                    .init(id: "2", login: "login2", password: "password2", url: "https://example.com")
                ],
                modifiedSince: "9012"
            )
        )

        let bodies = try XCTUnwrap(apiMock.createRequestCallArgs.map(\.body))
        XCTAssertEqual(apiMock.createRequestCallCount, 3)
        XCTAssertEqual(bodies.count, 3)

        var payloadCount = 3

        for body in bodies.compactMap({$0}) {
            do {
                let payload = try JSONDecoder.snakeCaseKeys.decode(BookmarksPayload.self, from: body)
                XCTAssertEqual(payload, bookmarks)
                payloadCount -= 1
            } catch {
                do {
                    let payload = try JSONDecoder.snakeCaseKeys.decode(SettingsPayload.self, from: body)
                    XCTAssertEqual(payload, settings)
                    payloadCount -= 1
                } catch {
                    let payload = try JSONDecoder.snakeCaseKeys.decode(AutofillPayload.self, from: body)
                    XCTAssertEqual(payload, autofill)
                    payloadCount -= 1
                }
            }
        }

        XCTAssertEqual(payloadCount, 0)
    }

    func testThatForMultipleDataProvidersErrorsFromAllFeaturesAreThrown() async throws {

        struct DataProviderError: Error, Equatable {
            let feature: Feature
        }

        let feature1 = Feature(name: "bookmarks")
        var dataProvider1 = DataProvidingMock(feature: feature1)
        dataProvider1.lastSyncTimestamp = "1234"
        dataProvider1._fetchChangedObjects = { _ in throw DataProviderError(feature: feature1) }

        let feature2 = Feature(name: "settings")
        var dataProvider2 = DataProvidingMock(feature: feature2)
        dataProvider2.lastSyncTimestamp = "5678"
        dataProvider2._fetchChangedObjects = { _ in throw DataProviderError(feature: feature2) }

        let feature3 = Feature(name: "autofill")
        var dataProvider3 = DataProvidingMock(feature: feature3)
        dataProvider3.lastSyncTimestamp = "9012"
        dataProvider3._fetchChangedObjects = { _ in [] }

        let engine = Engine(dataProviders: [dataProvider1, dataProvider2, dataProvider3], storage: storage, crypter: crypter, api: apiMock, endpoints: endpoints)

        request.result = .init(data: "{\"autofill\":{\"last_modified\":\"1234\",\"entries\":[]}}".data(using: .utf8)!, response: .init())

        await assertThrowsAnyError({
            try await engine.sync(fetchOnly: false)
        }, errorHandler: { error in
            guard let syncOperationError = error as? SyncOperationError else {
                XCTFail("Unexpected error type: \(type(of: error))")
                return
            }
            XCTAssertEqual(syncOperationError.perFeatureErrors.count, 2)
            XCTAssertEqual(syncOperationError.perFeatureErrors[feature1] as? DataProviderError, DataProviderError(feature: feature1))
            XCTAssertEqual(syncOperationError.perFeatureErrors[feature2] as? DataProviderError, DataProviderError(feature: feature2))
        })
    }

    func testThatSentModelsAreEchoedInResults() async throws {
        let objectsToSync = [
            Syncable(jsonObject: ["id": "1", "name": "bookmark1", "url": "https://example.com"]),
            Syncable(jsonObject: ["id": "2", "name": "bookmark2", "url": "https://example.com"]),
        ]
        var dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        var sentModels: [Syncable] = []
        dataProvider.lastSyncTimestamp = "1234"
        dataProvider._fetchChangedObjects = { _ in objectsToSync }
        dataProvider.handleSyncResponse = { sent, _, _, _, _ in
            sentModels = sent
        }

        let engine = Engine(dataProviders: [dataProvider], storage: storage, crypter: crypter, api: apiMock, endpoints: endpoints)

        request.result = .init(data: nil, response: HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 304, httpVersion: nil, headerFields: nil)!)

        try await engine.sync(fetchOnly: false)

        XCTAssertTrue(try sentModels.isJSONRepresentationEquivalent(to: objectsToSync))
    }
}

private extension Array where Element == Syncable {
    func isJSONRepresentationEquivalent(to other: [Element]) throws -> Bool {
        let thisData = try JSONSerialization.data(withJSONObject: map(\.payload))
        let otherData = try JSONSerialization.data(withJSONObject: other.map(\.payload))
        return thisData == otherData
    }
}

struct FeaturePayload<Model: Decodable & Equatable>: Decodable, Equatable {
    let updates: [Model]
    let modifiedSince: String
}

struct BookmarksPayload: Decodable, Equatable {
    let bookmarks: FeaturePayload<Bookmark>

    struct Bookmark: Decodable, Equatable {
        let id: String
        let name: String
        let url: String
    }
}

struct SettingsPayload: Decodable, Equatable {
    let settings: FeaturePayload<Setting>

    struct Setting: Decodable, Equatable {
        let key: String
        let value: String
    }
}

struct AutofillPayload: Decodable, Equatable {
    let autofill: FeaturePayload<Autofill>

    struct Autofill: Decodable, Equatable {
        let id: String
        let login: String
        let password: String
        let url: String
    }
}
