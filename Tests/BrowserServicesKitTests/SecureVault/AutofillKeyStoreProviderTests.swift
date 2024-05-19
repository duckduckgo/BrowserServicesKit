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

    func testWhenReadData_AndValueIsFound_NoFallbackSearchIsPerformed() throws {

        try AutofillKeyStoreProvider.EntryName.allCases.forEach { entry in
            // Given
            let keychainService = MockKeychainService()
            keychainService.mode = .v3Found
            let sut = AutofillKeyStoreProvider(keychainService: keychainService)

            // When
            let result = try sut.readData(named: entry.keychainIdentifier, serviceName: sut.keychainServiceName)

            // Then
            XCTAssertEqual(keychainService.itemMatchingCallCount, 1)
            XCTAssertEqual(String(decoding: result!, as: UTF8.self), "Mock Keychain data!")
        }
    }

    func testWhenReadData_AndNoValuesFound_AllFallbackSearchesArePerformed() throws {

        try AutofillKeyStoreProvider.EntryName.allCases.forEach { entry in
            // Given
            let keychainService = MockKeychainService()
            let sut = AutofillKeyStoreProvider(keychainService: keychainService)

            // When
            _ = try sut.readData(named: entry.keychainIdentifier, serviceName: sut.keychainServiceName)

            // Then
            XCTAssertEqual(keychainService.itemMatchingCallCount, 3)
        }
    }

    func testWhenReadData_AndV3ValueNotFound_V2SearchIsPerformed() throws {

        try AutofillKeyStoreProvider.EntryName.allCases.forEach { entry in
            // Given
            let keychainService = MockKeychainService()
            keychainService.mode = .v2Found
            let sut = AutofillKeyStoreProvider(keychainService: keychainService)

            // When
            let result = try sut.readData(named: entry.keychainIdentifier, serviceName: sut.keychainServiceName)

            // Then
            XCTAssertEqual(keychainService.itemMatchingCallCount, 2)
            XCTAssertEqual(keychainService.latestItemMatchingQuery[kSecAttrAccount as String] as! String, entry.rawValue)
            XCTAssertEqual(keychainService.latestItemMatchingQuery[kSecAttrService as String] as! String, AutofillKeyStoreProvider.Constants.v2ServiceName)
            XCTAssertEqual(String(decoding: result!, as: UTF8.self), "Mock Keychain data!")
        }
    }

    func testWhenReadData_AndV3OrV2ValueNotFound_V1SearchIsPerformed() throws {

        try AutofillKeyStoreProvider.EntryName.allCases.forEach { entry in
            // Given
            let keychainService = MockKeychainService()
            keychainService.mode = .v1Found
            let sut = AutofillKeyStoreProvider(keychainService: keychainService)

            // When
            _ = try sut.readData(named: entry.keychainIdentifier, serviceName: sut.keychainServiceName)

            // Then
            XCTAssertEqual(keychainService.itemMatchingCallCount, 3)
            XCTAssertEqual(keychainService.latestItemMatchingQuery[kSecAttrAccount as String] as! String, entry.rawValue)
            XCTAssertEqual(keychainService.latestItemMatchingQuery[kSecAttrService as String] as! String, AutofillKeyStoreProvider.Constants.v1ServiceName)
        }
    }

    func testWhenReadData_AndV2ValueFound_ThenWritesValueToNewStorageWithCorrectAttributes() throws {

        try AutofillKeyStoreProvider.EntryName.allCases.forEach { entry in
            // Given
            let keychainService = MockKeychainService()
            keychainService.mode = .v2Found
            let sut = AutofillKeyStoreProvider(keychainService: keychainService)

            // When
            let result = try sut.readData(named: entry.keychainIdentifier, serviceName: sut.keychainServiceName)

            // Then
            XCTAssertEqual(keychainService.addCallCount, 1)
            XCTAssertEqual(keychainService.latestAddQuery[kSecAttrAccount as String] as! String, entry.keychainIdentifier)
            XCTAssertEqual(keychainService.latestAddQuery[kSecAttrService as String] as! String, AutofillKeyStoreProvider.Constants.v3ServiceName)
            XCTAssertEqual(String(decoding: result!, as: UTF8.self), "Mock Keychain data!")
        }
    }

    func testWhenReadData_AndV1ValueFound_ThenWritesValueToNewStorageWithCorrectAttributes() throws {

        try AutofillKeyStoreProvider.EntryName.allCases.forEach { entry in
            // Given
            let keychainService = MockKeychainService()
            keychainService.mode = .v1Found
            let sut = AutofillKeyStoreProvider(keychainService: keychainService)

            // When
            _ = try sut.readData(named: entry.keychainIdentifier, serviceName: sut.keychainServiceName)

            // Then
            XCTAssertEqual(keychainService.addCallCount, 1)
            XCTAssertEqual(keychainService.latestAddQuery[kSecAttrAccount as String] as! String, entry.keychainIdentifier)
            XCTAssertEqual(keychainService.latestAddQuery[kSecAttrService as String] as! String, AutofillKeyStoreProvider.Constants.v3ServiceName)
        }
    }

    func testWhenWriteData_correctKeychainAccessibilityValueIsUsed() throws {
        try AutofillKeyStoreProvider.EntryName.allCases.forEach { entry in
            // Given
            let originalString = "Mock Keychain data!"
            let data = originalString.data(using: .utf8)!
            let encodedString = data.base64EncodedString()
            let mockData = encodedString.data(using: .utf8)!
            let keychainService = MockKeychainService()
            let sut = AutofillKeyStoreProvider(keychainService: keychainService)

            // When
            _ = try sut.writeData(mockData, named: entry.keychainIdentifier, serviceName: sut.keychainServiceName)

            // Then
            XCTAssertEqual(keychainService.addCallCount, 1)
            XCTAssertEqual(keychainService.latestAddQuery[kSecAttrAccessible as String] as! String, kSecAttrAccessibleWhenUnlocked as String)
        }
    }
}
