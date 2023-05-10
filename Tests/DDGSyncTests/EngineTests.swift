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
    var handleInitialSyncResponse: ([Syncable], String?, Crypting) async throws -> Void = { _,_,_ in }
    var handleSyncResponse: ([Syncable], [Syncable], Date, String?, Crypting) async throws -> Void = { _,_,_,_,_ in }

    func prepareForFirstSync() {
        _prepareForFirstSync()
    }

    func fetchChangedObjects(encryptedUsing crypter: Crypting) async throws -> [Syncable] {
        try await _fetchChangedObjects(crypter)
    }

    func handleInitialSyncResponse(received: [Syncable], serverTimestamp: String?, crypter: Crypting) async throws {
        try await handleInitialSyncResponse(received, serverTimestamp, crypter)
    }

    func handleSyncResponse(sent: [Syncable], received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws {
        try await handleSyncResponse(sent, received, clientTimestamp, serverTimestamp, crypter)
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
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        let engine = Engine(dataProviders: [dataProvider], storage: storage, crypter: crypter, api: apiMock, endpoints: endpoints)

        request.error = .noResponseBody
        await assertThrowsError(SyncError.noResponseBody) {
            try await engine.sync(fetchOnly: false)
        }
        XCTAssertEqual(apiMock.createRequestCallCount, 1)
        XCTAssertEqual(apiMock.createRequestCallArgs[0].method, .GET)
    }

    func testWhenThereAreChangesThenPatchRequestIsFired() async throws {
        var dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        dataProvider.lastSyncTimestamp = "1234"
        dataProvider._fetchChangedObjects = { _ in
            [Syncable(jsonObject: [:])]
        }
        let engine = Engine(dataProviders: [dataProvider], storage: storage, crypter: crypter, api: apiMock, endpoints: endpoints)

        request.error = .noResponseBody
        await assertThrowsError(SyncError.noResponseBody) {
            try await engine.sync(fetchOnly: false)
        }
        XCTAssertEqual(apiMock.createRequestCallCount, 1)
        XCTAssertEqual(apiMock.createRequestCallArgs[0].method, .PATCH)
    }

    func testThatMultipleDataProvidersGetSerializedIntoRequestPayload() async throws {
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
        await assertThrowsError(SyncError.noResponseBody) {
            try await engine.sync(fetchOnly: false)
        }

        let body = try XCTUnwrap(apiMock.createRequestCallArgs[0].body)
        XCTAssertEqual(
            try JSONDecoder.snakeCaseKeys.decode(MultiProviderRequestPayload.self, from: body), 
            MultiProviderRequestPayload(
                bookmarks: .init(updates: [
                    .init(id: "1", name: "bookmark1", url: "https://example.com"),
                    .init(id: "2", name: "bookmark2", url: "https://example.com")
                ],
                modifiedSince: "1234"),
                settings: .init(updates: [
                    .init(key: "setting-a", value: "value-a"),
                    .init(key: "setting-b", value: "value-b")
                ], modifiedSince: "5678"),
                autofill: .init(updates: [
                    .init(id: "1", login: "login1", password: "password1", url: "https://example.com"),
                    .init(id: "2", login: "login2", password: "password2", url: "https://example.com")
                ], modifiedSince: "9012")
            )
        )
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

private struct MultiProviderRequestPayload: Decodable, Equatable {
    let bookmarks: FeaturePayload<Bookmark>
    let settings: FeaturePayload<Setting>
    let autofill: FeaturePayload<Autofill>

    struct FeaturePayload<Model: Decodable & Equatable>: Decodable, Equatable {
        let updates: [Model]
        let modifiedSince: String
    }
    struct Bookmark: Decodable, Equatable {
        let id: String
        let name: String
        let url: String
    }
    struct Setting: Decodable, Equatable {
        let key: String
        let value: String
    }
    struct Autofill: Decodable, Equatable {
        let id: String
        let login: String
        let password: String
        let url: String
    }
}
