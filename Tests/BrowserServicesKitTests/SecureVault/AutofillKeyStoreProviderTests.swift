//
//  AutofillKeyStoreProviderTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import SecureStorageTestsUtils
@testable import BrowserServicesKit

final class AutofillKeyStoreProviderTests: XCTestCase {

    private enum Constants {
        static let legacyServiceName = "DuckDuckGo Secure Vault"
        static let defaultServiceName = "DuckDuckGo Secure Vault v2"
    }

    private enum EntryName: String, CaseIterable {

        case generatedPassword = "32A8C8DF-04AF-4C9D-A4C7-83096737A9C0"
        case l1Key = "79963A16-4E3A-464C-B01A-9774B3F695F1"
        case l2Key = "A5711F4D-7AA5-4F0C-9E4F-BE553F1EA299"

        var keyValue: String {
            (Bundle.main.bundleIdentifier ?? "com.duckduckgo") + rawValue
        }
    }

    func testWhenReadData_AndValueIsFound_NoFallbackSearchIsPerformed() throws {

        try EntryName.allCases.forEach { entry in
            // Given
            let keychainService = MockKeychainService()
            keychainService.mode = .bundleSpecificFound
            let sut = AutofillKeyStoreProvider(keychainService: keychainService)

            // When
            _ = try sut.readData(named: entry.keyValue, serviceName: sut.keychainServiceName)

            // Then
            XCTAssertEqual(keychainService.itemMatchingCallCount, 1)
        }
    }

    func testWhenReadData_AndValueNotFound_AllFallbackSearchesArePerformed() throws {

        try EntryName.allCases.forEach { entry in
            // Given
            let keychainService = MockKeychainService()
            let sut = AutofillKeyStoreProvider(keychainService: keychainService)

            // When
            _ = try sut.readData(named: entry.keyValue, serviceName: sut.keychainServiceName)

            // Then
            XCTAssertEqual(keychainService.itemMatchingCallCount, 3)
        }
    }

    func testWhenReadData_AndValueNotFound_NonBundleSpecificSearchIsPerformed() throws {

        try EntryName.allCases.forEach { entry in
            // Given
            let keychainService = MockKeychainService()
            keychainService.mode = .nonBundleSpecificFound
            let sut = AutofillKeyStoreProvider(keychainService: keychainService)

            // When
            _ = try sut.readData(named: entry.keyValue, serviceName: sut.keychainServiceName)

            // Then
            XCTAssertEqual(keychainService.itemMatchingCallCount, 2)
            XCTAssertEqual(keychainService.latestItemMatchingQuery[kSecAttrAccount as String] as! String, entry.rawValue)
            XCTAssertEqual(keychainService.latestItemMatchingQuery[kSecAttrService as String] as! String, Constants.defaultServiceName)
        }
    }

    func testWhenReadData_AndValueNotFound_V1SearchIsPerformed() throws {

        try EntryName.allCases.forEach { entry in
            // Given
            let keychainService = MockKeychainService()
            keychainService.mode = .v1Found
            let sut = AutofillKeyStoreProvider(keychainService: keychainService)

            // When
            _ = try sut.readData(named: entry.keyValue, serviceName: sut.keychainServiceName)

            // Then
            XCTAssertEqual(keychainService.itemMatchingCallCount, 3)
            XCTAssertEqual(keychainService.latestItemMatchingQuery[kSecAttrAccount as String] as! String, entry.rawValue)
            XCTAssertEqual(keychainService.latestItemMatchingQuery[kSecAttrService as String] as! String, Constants.legacyServiceName)
        }
    }

    func testWhenReadData_AndNonBundleSpecificValueFound_ThenWritesValueToNewStorageWithCorrectAttributes() throws {

        try EntryName.allCases.forEach { entry in
            // Given
            let keychainService = MockKeychainService()
            keychainService.mode = .nonBundleSpecificFound
            let sut = AutofillKeyStoreProvider(keychainService: keychainService)

            // When
            _ = try sut.readData(named: entry.keyValue, serviceName: sut.keychainServiceName)

            // Then
            XCTAssertEqual(keychainService.addCallCount, 1)
            XCTAssertEqual(keychainService.latestAddQuery[kSecAttrAccount as String] as! String, entry.keyValue)
            XCTAssertEqual(keychainService.latestAddQuery[kSecAttrService as String] as! String, Constants.defaultServiceName)
        }
    }

    func testWhenReadData_AndV1ValueFound_ThenWritesValueToNewStorageWithCorrectAttributes() throws {

        try EntryName.allCases.forEach { entry in
            // Given
            let keychainService = MockKeychainService()
            keychainService.mode = .v1Found
            let sut = AutofillKeyStoreProvider(keychainService: keychainService)

            // When
            _ = try sut.readData(named: entry.keyValue, serviceName: sut.keychainServiceName)

            // Then
            XCTAssertEqual(keychainService.addCallCount, 1)
            XCTAssertEqual(keychainService.latestAddQuery[kSecAttrAccount as String] as! String, entry.keyValue)
            XCTAssertEqual(keychainService.latestAddQuery[kSecAttrService as String] as! String, Constants.defaultServiceName)
        }
    }
}
