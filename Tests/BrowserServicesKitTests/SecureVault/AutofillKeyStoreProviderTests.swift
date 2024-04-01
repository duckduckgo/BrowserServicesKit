//
//  AutofillKeyStoreProviderTests.swift
//  DuckDuckGo
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
        // Given
        let keychainService = MockKeychainService()
        keychainService.mode = .bundleSpecificFound
        let sut = AutofillKeyStoreProvider(keychainService: keychainService)

        // When
        _ = try sut.readData(named: sut.l1KeyEntryName, serviceName: sut.keychainServiceName)

        // Then
        XCTAssertEqual(keychainService.itemMatchingCallCount, 1)
    }

    func testWhenReadData_AndValueNotFound_FallbackChecksArePerformed() throws {
        // Given
        let keychainService = MockKeychainService()
        let sut = AutofillKeyStoreProvider(keychainService: keychainService)

        // When
        _ = try sut.readData(named: sut.l1KeyEntryName, serviceName: sut.keychainServiceName)

        // Then
        XCTAssertEqual(keychainService.itemMatchingCallCount, 3)
    }

    func testWhenReadData_AndNonBundleSpecificValueFound_ThenWritesValueToNewStorage() throws {
        // Given
        let keychainService = MockKeychainService()
        keychainService.mode = .nonBundleSpecificFound
        let sut = AutofillKeyStoreProvider(keychainService: keychainService)

        // When
        _ = try sut.readData(named: sut.l1KeyEntryName, serviceName: sut.keychainServiceName)

        // Then
        XCTAssertEqual(keychainService.addCallCount, 1)
    }

    func testWhenReadData_AndV1ValueFound_ThenWritesValueToNewStorage() throws {
        // Given
        let keychainService = MockKeychainService()
        keychainService.mode = .v1Found
        let sut = AutofillKeyStoreProvider(keychainService: keychainService)

        // When
        _ = try sut.readData(named: sut.l1KeyEntryName, serviceName: sut.keychainServiceName)

        // Then
        XCTAssertEqual(keychainService.addCallCount, 2)
    }

}
