//
//  MockKeystoreProvider.swift
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
import SecureStorage

public class MockKeystoreProvider: SecureStorageKeyStoreProvider {

    public init() {}

    // swiftlint:disable identifier_name
    public var _l1Key: Data?
    public var _encryptedL2Key: Data?
    public var _generatedPassword: Data?
    public var _generatedPasswordCleared = false
    public var _lastEncryptedL2Key: Data?
    // swiftlint:enable identifier_name

    public var generatedPasswordEntryName: String {
        return ""
    }

    public var l1KeyEntryName: String {
        return ""
    }

    public var l2KeyEntryName: String {
        return ""
    }

    public var keychainServiceName: String {
        return ""
    }

    public func attributesForEntry(named: String, serviceName: String) -> [String: Any] {
        return [:]
    }

    public func storeGeneratedPassword(_ password: Data) throws {
    }

    public func generatedPassword() throws -> Data? {
        return _generatedPassword
    }

    public func clearGeneratedPassword() throws {
        _generatedPasswordCleared = true
    }

    public func storeL1Key(_ data: Data) throws {
    }

    public func l1Key() throws -> Data? {
        return _l1Key
    }

    public func storeEncryptedL2Key(_ data: Data) throws {
        _lastEncryptedL2Key = data
    }

    public func encryptedL2Key() throws -> Data? {
        return _encryptedL2Key
    }

}
