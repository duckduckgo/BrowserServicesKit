//
//  AccountManager.swift
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
import DDGSyncCrypto

struct AccountManager: AccountManaging {

    let endpoints: Endpoints
    let api: RemoteAPIRequestCreating
    let crypter: Crypting

    func createAccount(deviceName: String, deviceType: String) async throws -> SyncAccount {
        let deviceId = UUID().uuidString
        let userId = UUID().uuidString
        let password = UUID().uuidString

        let accountKeys = try crypter.createAccountCreationKeys(userId: userId, password: password)
        let encryptedDeviceName = try crypter.encryptAndBase64Encode(deviceName, using: accountKeys.primaryKey)
        let encryptedDeviceType = try crypter.encryptAndBase64Encode(deviceType, using: accountKeys.primaryKey)

        let hashedPassword = Data(accountKeys.passwordHash).base64EncodedString()
        let protectedEncyrptionKey = Data(accountKeys.protectedSecretKey).base64EncodedString()

        let params = Signup.Parameters(
            userId: userId,
            hashedPassword: hashedPassword,
            protectedEncryptionKey: protectedEncyrptionKey,
            deviceId: deviceId,
            deviceName: encryptedDeviceName,
            deviceType: encryptedDeviceType
        )

        guard let paramJson = try? JSONEncoder.snakeCaseKeys.encode(params) else {
            fatalError()
        }

        let request = api.createRequest(
            url: endpoints.signup,
            method: .POST,
            headers: [:],
            parameters: [:],
            body: paramJson,
            contentType: "application/json"
        )

        let result = try await request.execute()

        guard let body = result.data else {
            throw SyncError.noResponseBody
        }

        guard let result = try? JSONDecoder.snakeCaseKeys.decode(Signup.Result.self, from: body) else {
            throw SyncError.unableToDecodeResponse("Failed to decode signup result")
        }

        return SyncAccount(deviceId: deviceId,
                           deviceName: deviceName,
                           deviceType: deviceType,
                           userId: userId,
                           primaryKey: Data(accountKeys.primaryKey),
                           secretKey: Data(accountKeys.secretKey),
                           token: result.token)
    }

    func login(_ recoveryKey: SyncCode.RecoveryKey, deviceName: String, deviceType: String) async throws -> LoginResult {
        let deviceId = UUID().uuidString

        let recoveryInfo = try crypter.extractLoginInfo(recoveryKey: recoveryKey)
        let encryptedDeviceName = try crypter.encryptAndBase64Encode(deviceName, using: recoveryInfo.primaryKey)
        let encryptedDeviceType = try crypter.encryptAndBase64Encode(deviceType, using: recoveryInfo.primaryKey)

        let params = Login.Parameters(
            userId: recoveryInfo.userId,
            hashedPassword: recoveryInfo.passwordHash.base64EncodedString(),
            deviceId: deviceId,
            deviceName: encryptedDeviceName,
            deviceType: encryptedDeviceType
        )

        let paramJson = try JSONEncoder.snakeCaseKeys.encode(params)

        let request = api.createRequest(
            url: endpoints.login,
            method: .POST,
            headers: [:],
            parameters: [:],
            body: paramJson,
            contentType: "application/json"
        )

        let result = try await request.execute()

        guard let body = result.data else {
            throw SyncError.noResponseBody
        }

        print(String(data: body, encoding: .utf8) ?? "invalid result.data")
        guard let result = try? JSONDecoder.snakeCaseKeys.decode(Login.Result.self, from: body) else {
            throw SyncError.unableToDecodeResponse("Failed to decode login result")
        }

        guard let protectedSecretKey = Data(base64Encoded: result.protectedEncryptionKey) else {
            throw SyncError.invalidDataInResponse("protected_key missing from response")
        }

        let token = result.token

        let secretKey = try crypter.extractSecretKey(protectedSecretKey: protectedSecretKey, stretchedPrimaryKey: recoveryInfo.stretchedPrimaryKey)

        return LoginResult(
            account: SyncAccount(
                deviceId: params.deviceId,
                deviceName: deviceName,
                deviceType: deviceType,
                userId: recoveryInfo.userId,
                primaryKey: recoveryInfo.primaryKey,
                secretKey: secretKey,
                token: token
            ),
            devices: try result.devices.map {
                RegisteredDevice(
                    id: $0.deviceId,
                    name: try crypter.base64DecodeAndDecrypt($0.deviceName, using: recoveryInfo.primaryKey),
                    type: try crypter.base64DecodeAndDecrypt($0.deviceType, using: recoveryInfo.primaryKey)
                )
            }
        )
    }

    func logout(deviceId: String, token: String) async throws {
        let params = LogoutDevice.Parameters(deviceId: deviceId)

        guard let paramJson = try? JSONEncoder.snakeCaseKeys.encode(params) else {
            fatalError()
        }

        let request = api.createRequest(
            url: endpoints.logoutDevice,
            method: .POST,
            headers: ["Authorization": "Bearer \(token)"],
            parameters: [:],
            body: paramJson,
            contentType: "application/json"
        )

        let result = try await request.execute()

        guard let body = result.data else {
            throw SyncError.noResponseBody
        }

        print(String(data: body, encoding: .utf8) ?? "invalid result.data")
        guard let result = try? JSONDecoder.snakeCaseKeys.decode(LogoutDevice.Result.self, from: body) else {
            throw SyncError.unableToDecodeResponse("Failed to decode login result")
        }

        guard result.deviceId == deviceId else {
            throw SyncError.unexpectedResponseBody
        }
    }

    struct Signup {

        struct Result: Decodable {
            let userId: String
            let token: String
        }

        struct Parameters: Encodable {
            let userId: String
            let hashedPassword: String
            let protectedEncryptionKey: String
            let deviceId: String
            let deviceName: String
            let deviceType: String
        }
    }

    struct Login {

        struct Result: Decodable {
            let devices: [Device]
            let token: String
            let protectedEncryptionKey: String
        }

        struct Device: Decodable {
            let deviceId: String
            let deviceName: String
            let deviceType: String
        }
        
        struct Parameters: Encodable {
            let userId: String
            let hashedPassword: String
            let deviceId: String
            let deviceName: String
            let deviceType: String
        }

    }

    struct LogoutDevice {

        struct Result: Decodable {
            let deviceId: String
        }

        struct Parameters: Encodable {
            let deviceId: String
        }
    }
}
