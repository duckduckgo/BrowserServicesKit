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

public struct SyncAccount: Codable {
    public let deviceId: String
    public let deviceName: String
    public let deviceType: String
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
    public let type: String
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
