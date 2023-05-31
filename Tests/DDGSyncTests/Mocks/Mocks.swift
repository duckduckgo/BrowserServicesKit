//
//  Mocks.swift
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
import Foundation
@testable import DDGSync

extension SyncAccount {
    static var mock: SyncAccount {
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
    }
}

extension RegisteredDevice {
    static var mock: RegisteredDevice {
        RegisteredDevice(id: "1", name: "2", type: "3")
    }
}

extension LoginResult {
    static var mock: LoginResult {
        LoginResult(account: .mock, devices: [.mock])
    }
}

struct AccountManagingMock: AccountManaging {
    func createAccount(deviceName: String, deviceType: String) async throws -> SyncAccount {
        .mock
    }

    func deleteAccount(_ account: SyncAccount) async throws {}

    func login(_ recoveryKey: SyncCode.RecoveryKey, deviceName: String, deviceType: String) async throws -> LoginResult {
        .mock
    }

    func refreshToken(_ account: SyncAccount, deviceName: String) async throws -> LoginResult {
        .mock
    }

    func logout(deviceId: String, token: String) async throws {}

    func fetchDevicesForAccount(_ account: SyncAccount) async throws -> [RegisteredDevice] {
        [.mock]
    }
}

final class SchedulerMock: SchedulingInternal {
    var isEnabled: Bool = false

    let startSyncPublisher: AnyPublisher<Void, Never>

    init() {
        startSyncPublisher = startSyncSubject.eraseToAnyPublisher()
    }

    func notifyDataChanged() {
        if isEnabled {
            startSyncSubject.send(())
        }
    }

    func notifyAppLifecycleEvent() {
        if isEnabled {
            startSyncSubject.send(())
        }
    }

    func requestSyncImmediately() {
        if isEnabled {
            startSyncSubject.send(())
        }
    }

    private var startSyncSubject = PassthroughSubject<Void, Never>()
}

struct MockSyncDepenencies: SyncDependencies {
    var endpoints: Endpoints = Endpoints(baseUrl: URL(string: "https://dev.null")!)
    var account: AccountManaging = AccountManagingMock()
    var api: RemoteAPIRequestCreating = RemoteAPIRequestCreatingMock()
    var secureStore: SecureStoring = SecureStorageStub()
    var crypter: CryptingInternal = CryptingMock()
    var scheduler: SchedulingInternal = SchedulerMock()
    var log: OSLog = .default

    var request = HTTPRequestingMock()

    init() {
        (api as! RemoteAPIRequestCreatingMock).request = request
    }

    func createRemoteConnector(_ connectInfo: ConnectInfo) throws -> RemoteConnecting {
        try RemoteConnector(crypter: crypter, api: api, endpoints: endpoints, connectInfo: connectInfo)
    }

    func createRecoveryKeyTransmitter() throws -> RecoveryKeyTransmitting {
        RecoveryKeyTransmitter(endpoints: endpoints, api: api, storage: secureStore, crypter: crypter)
    }
}

final class MockDataProvidersSource: DataProvidersSource {
    var dataProviders: [DataProviding] = []

    func makeDataProviders() -> [DataProviding] {
        dataProviders
    }
}

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

struct CryptingMock: CryptingInternal {

    var _encryptAndBase64Encode: (String) throws -> String = { "encrypted_\($0)" }
    var _base64DecodeAndDecrypt: (String) throws -> String = { $0.dropping(prefix: "encrypted_") }

    func encryptAndBase64Encode(_ value: String) throws -> String {
        try _encryptAndBase64Encode(value)
    }

    func base64DecodeAndDecrypt(_ value: String) throws -> String {
        try _base64DecodeAndDecrypt(value)
    }

    func encryptAndBase64Encode(_ value: String, using secretKey: Data?) throws -> String {
        try _encryptAndBase64Encode(value)
    }

    func base64DecodeAndDecrypt(_ value: String, using secretKey: Data?) throws -> String {
        try _base64DecodeAndDecrypt(value)
    }

    func seal(_ data: Data, secretKey: Data) throws -> Data {
        data
    }

    func unseal(encryptedData: Data, publicKey: Data, secretKey: Data) throws -> Data {
        encryptedData
    }

    func createAccountCreationKeys(userId: String, password: String) throws -> AccountCreationKeys {
        AccountCreationKeys(primaryKey: Data(), secretKey: Data(), protectedSecretKey: Data(), passwordHash: Data())
    }

    func extractLoginInfo(recoveryKey: SyncCode.RecoveryKey) throws -> ExtractedLoginInfo {
        ExtractedLoginInfo(userId: "user", primaryKey: Data(), passwordHash: Data(), stretchedPrimaryKey: Data())
    }

    func extractSecretKey(protectedSecretKey: Data, stretchedPrimaryKey: Data) throws -> Data {
        Data()
    }

    func prepareForConnect() throws -> ConnectInfo {
        ConnectInfo(deviceID: "1234", publicKey: Data(), secretKey: Data())
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

    func handleSyncError(_ error: Error) {
        handleSyncError(error)
    }
}
