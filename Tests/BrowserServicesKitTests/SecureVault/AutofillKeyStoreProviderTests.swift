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
        let sut = AutofillKeyStoreProvider(keychainService: keychainService)

        // When
        let _ = try sut.readData(named: sut.l1KeyEntryName, serviceName: sut.keychainServiceName)

        // Then
        XCTAssertEqual(keychainService.itemMatchingCallCount, 1)
    }

    func testWhenReadData_AndValueNotFound_FallbackSearchIsPerformed() throws {
        // Given
        let keychainService = MockKeychainService()
        keychainService.willFindItem = false
        let sut = AutofillKeyStoreProvider(keychainService: keychainService)

        // When
        let _ = try sut.readData(named: sut.l1KeyEntryName, serviceName: sut.keychainServiceName)

        // TODO: ---
        // THESE TESTS FAIL AS CURRENTLY MIGRATION IS NOT HANDLED CORRECTLY, SEE AUTOFILLKEYSTOREPROVIDER

        // Then
        XCTAssertEqual(keychainService.itemMatchingCallCount, 2)
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
