//
//  RemoteAPIRequestCreating.swift
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

struct RemoteConnector: RemoteConnecting {
    
    let code: String
    let connectInfo: ConnectInfo

    let account: AccountManaging
    let crypter: Crypting
    let api: RemoteAPIRequestCreating
    let endpoints: Endpoints

    init(account: AccountManaging, crypter: Crypting, api: RemoteAPIRequestCreating, endpoints: Endpoints, connectInfo: ConnectInfo) throws {
        self.account = account
        self.crypter = crypter
        self.api = api
        self.endpoints = endpoints
        self.connectInfo = connectInfo
        self.code = try connectInfo.toCode()
    }

    func connect(deviceName: String, deviceType: String) async throws -> LoginResult {
        while true {
            // If the UI closes it should cancel the task
            try Task.checkCancellation()

            if let encryptedRecoveryKey = try await fetchEncryptedRecoveryKey() {
                let recoveryKey = try decryptEncryptedRecoveryKey(encryptedRecoveryKey)
                return try await account.login(recoveryKey, deviceName: deviceName, deviceType: deviceType)
            }

            // Wait for 5 seconds before polling again
            try await Task.sleep(nanoseconds: 5 * 1_000_000_000)
        }
    }

    private func decryptEncryptedRecoveryKey(_ encryptedRecoveryKey: Data) throws -> SyncCode.RecoveryKey {
        return .init(userId: "", primaryKey: Data())
    }

    private func fetchEncryptedRecoveryKey() async throws -> Data? {
        let url = endpoints.connect.appendingPathComponent(connectInfo.deviceID)

        let request = api.createRequest(url: url, method: .GET,
                              headers: [:],
                              parameters: [:],
                              body: nil,
                              contentType: nil)

        do {
            let result = try await request.execute()
            guard let data = result.data else {
                throw SyncError.invalidDataInResponse("No body in successful GET on /connect")
            }
            return data
        } catch SyncError.unexpectedStatusCode(let statusCode) {
            if statusCode == 404 {
                return nil
            }
            throw SyncError.unexpectedStatusCode(statusCode)
        }
    }

    struct ConnectPostRequest: Codable {

        let deviceId: String
        let encryptedRecoveryKey: Data

    }

}

extension ConnectInfo {

    func toCode() throws -> String {
        return try SyncCode(connect: .init(deviceId: deviceID, secretKey: publicKey))
            .toJSON()
            .base64EncodedString()
    }

}
