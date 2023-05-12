//
//  File.swift
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

import Foundation

public struct SyncAccount: Codable, Sendable {
    public let deviceId: String
    public let deviceName: String
    public let deviceType: String
    public let userId: String
    public let primaryKey: Data
    public let secretKey: Data
    public let token: String?

    /// Convenience var which calls `SyncCode().toJSON().base64EncodedString()`
    public var recoveryCode: String? {
        do {
            let json = try SyncCode(recovery: .init(userId: userId, primaryKey: primaryKey)).toJSON()
            return json.base64EncodedString()
        } catch {
            assertionFailure(error.localizedDescription)
            return nil
        }
    }
}

public struct RegisteredDevice: Codable, Sendable {

    public let id: String
    public let name: String
    public let type: String

    // Remove this when the server change is made to remove the device_ prefix
    enum CodingKeys: String, CodingKey {
        case id = "deviceId"
        case name = "deviceName"
        case type = "deviceType"
    }

}

public struct AccountCreationKeys {
    public let primaryKey: Data
    public let secretKey: Data
    public let protectedSecretKey: Data
    public let passwordHash: Data
}

public struct ExtractedLoginInfo {
    public let userId: String
    public let primaryKey: Data
    public let passwordHash: Data
    public let stretchedPrimaryKey: Data
}

public struct ConnectInfo {
    public let deviceID: String
    public let publicKey: Data
    public let secretKey: Data
}

public struct SyncCode: Codable {

    public enum Base64Error: Error {
        case error
    }

    public struct RecoveryKey: Codable, Sendable {
        let userId: String
        let primaryKey: Data
    }

    public struct ConnectCode: Codable, Sendable {
        let deviceId: String
        let secretKey: Data
    }

    public var recovery: RecoveryKey?
    public var connect: ConnectCode?

    public static func decode(_ data: Data) throws -> Self {
        return try JSONDecoder.snakeCaseKeys.decode(self, from: data)
    }

    public func toJSON() throws -> Data {
        return try JSONEncoder.snakeCaseKeys.encode(self)
    }

    public static func decodeBase64String(_ string: String) throws -> Self {
        guard let data = Data(base64Encoded: string) else {
            throw Base64Error.error
        }
        return try Self.decode(data)
    }

}
