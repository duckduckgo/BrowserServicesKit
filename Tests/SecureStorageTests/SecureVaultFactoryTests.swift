//
//  MockVault.swift
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
import XCTest
import GRDB
import SecureStorage

protocol MockDatabaseProvider: SecureStorageDatabaseProvider {

    func storeSomeData(string: String) throws

    func getStoredData() throws -> String?

}

final class ConcreteMockDatabaseProvider: MockDatabaseProvider {

    init(file: URL = URL(string: "https://duckduckgo.com/")!, key: Data = Data()) throws {}

    static func recreateDatabase(withKey key: Data) throws -> Self {
        return try ConcreteMockDatabaseProvider(file: URL(string: "https://duckduckgo.com")!, key: Data()) as! Self
    }

    var storedData: String?

    func storeSomeData(string: String) throws {
        self.storedData = string
    }

    func getStoredData() throws -> String? {
        return self.storedData
    }

}

protocol MockSecureVault: SecureVault {

    func storeSomeData(string: String) throws

    func getStoredData() throws -> String?

}

final class ConcreteMockSecureVault<T: MockDatabaseProvider>: MockSecureVault {

    public typealias MockStorageProviders = SecureStorageProviders<T>

    private let providers: MockStorageProviders

    public required init(providers: MockStorageProviders) {
        self.providers = providers
    }

    func storeSomeData(string: String) throws {
        try self.providers.database.storeSomeData(string: string)
    }

    func getStoredData() throws -> String? {
        return try self.providers.database.getStoredData()
    }
}

typealias MockVaultFactory = SecureVaultFactory<ConcreteMockSecureVault<ConcreteMockDatabaseProvider>>

let MockSecureVaultFactory = SecureVaultFactory<ConcreteMockSecureVault>(
    makeCryptoProvider: {
        return MockCryptoProvider()
    }, makeKeyStoreProvider: {
        let provider = MockKeyStoreProvider()
        provider._l1Key = "key".data(using: .utf8)
        return provider
    }, makeDatabaseProvider: { key, _ in
        return try ConcreteMockDatabaseProvider(key: key)
    }
)

// MARK: - Tests

final class MockVaultTests: XCTestCase {

    func testCreatingMockVaultWithSecureVaultFactory() throws {
        let vault = try MockSecureVaultFactory.makeVault(errorReporter: nil)
        let storedString = "hello, world!"

        try vault.storeSomeData(string: storedString)
        XCTAssertEqual(try vault.getStoredData(), storedString)
    }

}
