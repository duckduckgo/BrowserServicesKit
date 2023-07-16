//
//  SecureVaultCryptoProvider.swift
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

import Foundation

public protocol SecureVaultCryptoProvider {

    func generateSecretKey() throws -> Data

    func generatePassword() throws -> Data

    func deriveKeyFromPassword(_ password: Data) throws -> Data

    func encrypt(_ data: Data, withKey key: Data) throws -> Data

    func decrypt(_ data: Data, withKey key: Data) throws -> Data

    func hashData(_ data: Data) throws -> String?

    func hashData(_ data: Data, salt: Data?) throws -> String?

    var hashingSalt: Data? { get }

}

public extension SecureVaultCryptoProvider {

    func hashData(_ data: Data) throws -> String? {
        guard let salt = hashingSalt else { return nil }
        return try hashData(data, salt: salt)
    }

}
