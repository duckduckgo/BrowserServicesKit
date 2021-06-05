//
//  CryptoProviderTests.swift
//  
//
//  Created by Chris Brind on 19/04/2021.
//

import Foundation

import XCTest
import CryptoKit
@testable import BrowserServicesKit

class CryptoProviderTests: XCTestCase {

    func testWhenDecryptingWithKeyFromInvalidPassword_ThenThrowsInvalidPasswordError() throws {

        let provider = DefaultCryptoProvider()

        let example = "example"
        let exampleData = example.data(using: .utf8)!

        let password = "password"
        let passwordData = password.data(using: .utf8)!

        let derivedKey = try provider.deriveKeyFromPassword(passwordData)
        let encrypted = try provider.encrypt(exampleData, withKey: derivedKey)

        let wrongPasswordKey = try provider.deriveKeyFromPassword("wrong".data(using: .utf8)!)
        do {
            _ = try provider.decrypt(encrypted, withKey: wrongPasswordKey)
            XCTFail("Expected throws")
        } catch {
            if case SecureVaultError.invalidPassword = error {
                // We good
            } else {
                XCTFail("Expected invalidPassword, received \(error)")
            }
        }

    }

    func testWhenDataEncryptedWithKey_ThenItCanBeDecryptedWithKey() throws {

        let provider = DefaultCryptoProvider()

        let example = "password"
        let exampleData = example.data(using: .utf8)!

        let key = try provider.generateSecretKey()

        let encrypted = try provider.encrypt(exampleData, withKey: key)
        XCTAssertNotEqual(encrypted, exampleData)

        let decrypted = try provider.decrypt(encrypted, withKey: key)
        XCTAssertEqual(decrypted, exampleData)

    }

    func testWhenGeneratingASecretKey_ThenKeyHasRequiredLengthAndNonNilData() throws {
        let provider = DefaultCryptoProvider()
        let key = try provider.generateSecretKey()
        XCTAssertGreaterThanOrEqual(key.count, 32)
        XCTAssertGreaterThan(key.filter { $0 > 0 }.count, 0)
    }

    func testWhenDerivingAKeyFromAPassword_ThenKeyHasRequiredLengthAndNonNilData() throws {
        let provider = DefaultCryptoProvider()
        let key = try provider.deriveKeyFromPassword("password".data(using: .utf8)!)
        XCTAssertGreaterThanOrEqual(key.count, 32)
        XCTAssertGreaterThan(key.filter { $0 > 0 }.count, 0)
    }

    func testWhenGeneratingPassword_ThenPasswordHasRequiredLengthAndNonNilData() throws {
        let provider = DefaultCryptoProvider()
        let password = try provider.generatePassword()
        XCTAssertGreaterThanOrEqual(password.count, 32)
        XCTAssertGreaterThan(password.filter { $0 > 0 }.count, 0)
    }

}
