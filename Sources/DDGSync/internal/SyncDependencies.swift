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

import Foundation

protocol SyncDependencies {

    var endpoints: Endpoints { get }
    var account: AccountManaging { get }
    var api: RemoteAPIRequestCreating { get }
    var secureStore: SecureStoring { get }
    var responseHandler: ResponseHandling { get }
    var crypter: Crypting { get }

    func createUpdatesSender(_ persistence: LocalDataPersisting) throws -> UpdatesSending
    func createUpdatesFetcher(_ persistence: LocalDataPersisting) throws -> UpdatesFetching

}

public protocol AccountManaging {

    func createAccount(deviceName: String) async throws -> SyncAccount

    func login(recoveryKey: Data, deviceName: String) async throws -> (account: SyncAccount, devices: [RegisteredDevice])
    func logout(deviceId: String, token: String) async throws

}

public struct SyncAccount {

    public let deviceId: String
    public let deviceName: String
    public let userId: String
    public let primaryKey: Data
    public let secretKey: Data
    public let token: String?

    public var recoveryCode: String? {
        guard let userIdData = userId.data(using: .utf8) else { return nil }
        let recoveryCodeData = primaryKey + userIdData
        return recoveryCodeData.base64EncodedString()
    }
}

public struct RegisteredDevice: Codable {
    
    public let id: String
    public let name: String

}

public protocol SecureStoring {

    func persistAccount(_ account: SyncAccount) throws

    func account() throws -> SyncAccount?

    func removeAccount() throws
}

public protocol ResponseHandling {

    func handleUpdates(_ data: Data) async throws

}

public protocol UpdatesFetching {

    func fetch() async throws

}

public struct ExtractedLoginInfo {

    public let userId: String
    public let primaryKey: Data
    public let passwordHash: Data
    public let stretchedPrimaryKey: Data

}

public struct AccountCreationKeys {
    
    public let primaryKey: Data
    public let secretKey: Data
    public let protectedSecretKey: Data
    public let passwordHash: Data

}

public protocol Crypting {

    func encryptAndBase64Encode(_ value: String) throws -> String
    func encryptAndBase64Encode(_ value: String, using secretKey: Data?) throws -> String

    func base64DecodeAndDecrypt(_ value: String) throws -> String

    func createAccountCreationKeys(userId: String, password: String) throws ->
        AccountCreationKeys

    func extractLoginInfo(recoveryKey: Data) throws -> ExtractedLoginInfo

    func extractSecretKey(protectedSecretKey: Data, stretchedPrimaryKey: Data) throws -> Data

}

extension Crypting {
    func encryptAndBase64Encode(_ value: String) throws -> String {
        try encryptAndBase64Encode(value, using: nil)
    }
}

extension SyncAccount: Codable { // TODO does this make codable part public?
    
}
