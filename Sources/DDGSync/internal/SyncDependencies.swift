//
//  SyncDependencies.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Combine
import Common
import Foundation
import Persistence

protocol SyncDependenciesDebuggingSupport {
    func updateServerEnvironment(_ serverEnvironment: ServerEnvironment)
}

protocol SyncDependencies: SyncDependenciesDebuggingSupport {

    var endpoints: Endpoints { get }
    var account: AccountManaging { get }
    var api: RemoteAPIRequestCreating { get }
    var payloadCompressor: SyncPayloadCompressing { get }
    var keyValueStore: KeyValueStoring { get }
    var secureStore: SecureStoring { get }
    var crypter: CryptingInternal { get }
    var scheduler: SchedulingInternal { get }
    var privacyConfigurationManager: PrivacyConfigurationManaging { get }
    var errorEvents: EventMapping<SyncError> { get }
    var log: OSLog { get }

    func createRemoteConnector(_ connectInfo: ConnectInfo) throws -> RemoteConnecting
    func createRecoveryKeyTransmitter() throws -> RecoveryKeyTransmitting
}

protocol AccountManaging {

    func createAccount(deviceName: String, deviceType: String) async throws -> SyncAccount
    func deleteAccount(_ account: SyncAccount) async throws

    func login(_ recoveryKey: SyncCode.RecoveryKey, deviceName: String, deviceType: String) async throws -> LoginResult
    func refreshToken(_ account: SyncAccount, deviceName: String) async throws -> LoginResult

    func logout(deviceId: String, token: String) async throws

    func fetchDevicesForAccount(_ account: SyncAccount) async throws -> [RegisteredDevice]

}

protocol SecureStoring {
    func persistAccount(_ account: SyncAccount) throws
    func account() throws -> SyncAccount?
    func removeAccount() throws
}

protocol CryptingInternal: Crypting {

    func seal(_ data: Data, secretKey: Data) throws -> Data
    func unseal(encryptedData: Data, publicKey: Data, secretKey: Data) throws -> Data

    func createAccountCreationKeys(userId: String, password: String) throws ->
        AccountCreationKeys

    func extractLoginInfo(recoveryKey: SyncCode.RecoveryKey) throws -> ExtractedLoginInfo

    func extractSecretKey(protectedSecretKey: Data, stretchedPrimaryKey: Data) throws -> Data

    func prepareForConnect() throws -> ConnectInfo

}

enum HTTPRequestMethod: String {
    case GET
    case POST
    case PATCH
    case DELETE
}

struct HTTPResult {
    let data: Data?
    let response: HTTPURLResponse
}

protocol HTTPRequesting {
    func execute() async throws -> HTTPResult
}

protocol RemoteAPIRequestCreating {
    func createRequest(url: URL,
                       method: HTTPRequestMethod,
                       headers: [String: String],
                       parameters: [String: String],
                       body: Data?,
                       contentType: String?) -> HTTPRequesting
}

protocol RecoveryKeyTransmitting {

    func send(_ code: SyncCode.ConnectCode) async throws

}
