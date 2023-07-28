//
//  TestSecureVaultFactory.swift
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
@testable import BrowserServicesKit

//extension DefaultDatabaseProvider {
//    static let testKey = "test-key".data(using: .utf8)!
//
//    static func makeTestProvider() throws -> DefaultDatabaseProvider {
//        let databaseLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
//        return try DefaultDatabaseProvider(file: databaseLocation, key: testKey)
//    }
//}

extension AutofillVaultFactory {
    static func testFactory(databaseProvider: DefaultAutofillDatabaseProvider) -> AutofillVaultFactory {
        AutofillVaultFactory(makeCryptoProvider: {
            NoOpCryptoProvider()
        }, makeKeyStoreProvider: {
            let provider = MockKeystoreProvider()
            provider._l1Key = "l1".data(using: .utf8)
            provider._encryptedL2Key = "encrypted".data(using: .utf8)
            return provider
        }, makeDatabaseProvider: { _ in
            databaseProvider
        })
    }
}

//class TestSecureVaultFactory: AutofillVaultFactory {
//
//    var mockCryptoProvider = NoOpCryptoProvider()
//    var mockKeystoreProvider = MockKeystoreProvider()
//    var databaseProvider: DefaultDatabaseProvider
//
//    init(databaseProvider: DefaultDatabaseProvider) {
//        self.databaseProvider = databaseProvider
//        mockKeystoreProvider._l1Key = "l1".data(using: .utf8)
//        mockKeystoreProvider._encryptedL2Key = "encrypted".data(using: .utf8)
//        super.init()
//    }
//
//    override func makeCryptoProvider() -> SecureVaultCryptoProvider {
//        mockCryptoProvider
//    }
//
//    override func makeKeyStoreProvider() -> SecureVaultKeyStoreProvider {
//        mockKeystoreProvider
//    }
//
//    override func makeDatabaseProvider(key: Data) throws -> SecureVaultDatabaseProvider {
//        databaseProvider
//    }
//}
