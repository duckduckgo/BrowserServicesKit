//
//  VaultFactoryTests.swift
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

import XCTest
import SecureStorage
@testable import BrowserServicesKit

class VaultFactoryTests: XCTestCase {

    class VaultFactoryTestHarness: SecureVaultFactory {

        var mockCryptoProvider = MockCryptoProvider()
        var mockKeystoreProvider = MockKeystoreProvider()
        var mockDatabaseProvider = MockDatabaseProvider()

        override func makeCryptoProvider() -> SecureVaultCryptoProvider {
            return mockCryptoProvider
        }

        override func makeKeyStoreProvider() -> SecureVaultKeyStoreProvider {
            return mockKeystoreProvider
        }

        override func makeDatabaseProvider(key: Data) throws -> SecureVaultDatabaseProvider {
            return mockDatabaseProvider
        }

    }

    func test() throws {
        let testHarness = VaultFactoryTestHarness()
        testHarness.mockKeystoreProvider._l1Key = "samplekey".data(using: .utf8)
        _ = try testHarness.makeVault(errorReporter: nil)
    }

}
