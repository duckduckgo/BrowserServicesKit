//
//  DatabaseProviderTests.swift
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

import XCTest
@testable import BrowserServicesKit
import GRDB

// swiftlint:disable force_try
class DatabaseProviderTests: XCTestCase {

    private func deleteDbFile() throws {
        do {
            try FileManager.default.removeItem(atPath: (try DefaultDatabaseProvider.dbFile()).path)
        } catch let error as NSError {
            // File not found
            if error.domain != NSCocoaErrorDomain || error.code != 4 {
                throw error
            }
        }
    }

    let simpleL1Key = "simple-key".data(using: .utf8)!

    override func setUp() {
        super.setUp()
        try! deleteDbFile()
    }

    override func tearDown() {
        super.tearDown()
        try! deleteDbFile()
    }

    func test_when_account_delete_then_credential_is_deleted() throws {
        let database = try DefaultDatabaseProvider(key: simpleL1Key)
        let account = SecureVaultModels.WebsiteAccount(username: "brindy", domain: "example.com")
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8)!)
        let accountId = try database.storeWebsiteCredentials(credentials)

        try database.deleteWebsiteCredentialsForAccountId(accountId)

        try database.db.read {
            XCTAssertEqual(try Row.fetchAll($0, sql: "select * from \(SecureVaultModels.WebsiteCredentials.databaseTableName)").count, 0)
        }

    }

    func test_when_credentials_stored_then_is_included_in_list_of_accounts() throws {
        let database = try DefaultDatabaseProvider(key: simpleL1Key) as SecureVaultDatabaseProvider
        for i in 0 ..< 10 {
            let account = SecureVaultModels.WebsiteAccount(username: "brindy", domain: "example\(i).com")
            let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8)!)
            try database.storeWebsiteCredentials(credentials)
        }

        XCTAssertEqual(10, try database.accounts().count)
    }

    func test_when_password_stored_then_password_can_be_retrieved() throws {
        let database = try DefaultDatabaseProvider(key: simpleL1Key) as SecureVaultDatabaseProvider
        let account = SecureVaultModels.WebsiteAccount(username: "brindy", domain: "example.com")

        // The db stores whatever Data it is given so it will alredy be encrypted by this point
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8)!)
        try database.storeWebsiteCredentials(credentials)

        let storedAccount = try database.websiteAccountsForDomain("example.com")[0]
        let storedCredentials = try database.websiteCredentialsForAccountId(storedAccount.id!)
        XCTAssertNotNil(storedCredentials)
        XCTAssertEqual("password", String(data: storedCredentials!.password, encoding: .utf8))
    }

    func test_when_database_reopened_then_existing_data_still_exists() throws {

        func insert() throws {
            let database = try DefaultDatabaseProvider(key: simpleL1Key) as SecureVaultDatabaseProvider
            let account = SecureVaultModels.WebsiteAccount(username: "brindy", domain: "example.com")
            let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8)!)
            try database.storeWebsiteCredentials(credentials)
        }

        func query() throws {
            let database = try DefaultDatabaseProvider(key: simpleL1Key) as SecureVaultDatabaseProvider
            let results = try database.websiteAccountsForDomain("example.com")
            XCTAssertEqual(results.count, 1)
        }

        try insert()
        try query()

    }

    func test_when_none_duplicate_records_stored_then_no_error_thrown() throws {
        let database = try DefaultDatabaseProvider(key: simpleL1Key) as SecureVaultDatabaseProvider
        for i in 0 ..< 1000 {
            let account = SecureVaultModels.WebsiteAccount(username: "brindy", domain: "example\(i).com")
            let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8)!)
            try database.storeWebsiteCredentials(credentials)
        }
    }

    func test_when_duplicate_record_stored_then_error_thrown() throws {
        let database = try DefaultDatabaseProvider(key: simpleL1Key) as SecureVaultDatabaseProvider
        let account = SecureVaultModels.WebsiteAccount(username: "brindy", domain: "example.com")
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8)!)
        XCTAssertEqual(1, try database.storeWebsiteCredentials(credentials))

        do {
            let id = try database.storeWebsiteCredentials(credentials)
            XCTFail("No exception for duplicate record, id: \(id)")
        } catch {
            switch error {
            case SecureVaultError.duplicateRecord: break
            default:
                XCTFail("Unexected exception \(error)")
            }
        }

    }

    func test_when_existing_record_stored_then_last_updated_date_is_updated() throws {
        let database = try DefaultDatabaseProvider(key: simpleL1Key) as SecureVaultDatabaseProvider
        let account = SecureVaultModels.WebsiteAccount(username: "brindy", domain: "example.com")
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8)!)
        try database.storeWebsiteCredentials(credentials)

        let storedAccount = try database.websiteAccountsForDomain("example.com")[0]
        var storedCredentials = try database.websiteCredentialsForAccountId(storedAccount.id!)!

        sleep(2)

        storedCredentials.password = "updated".data(using: .utf8)!
        try database.storeWebsiteCredentials(storedCredentials)

        let results = try database.websiteAccountsForDomain("example.com")
        XCTAssertEqual(1, results.count)

        let updatedAccount = results[0]
        XCTAssertNotNil(updatedAccount.lastUpdated)
        XCTAssertGreaterThan(updatedAccount.lastUpdated.timeIntervalSince(storedAccount.lastUpdated), 1)
    }

    func test_when_record_stored_then_can_be_retrieved_and_is_allocated_id_and_dates() throws {
        let database = try DefaultDatabaseProvider(key: simpleL1Key) as SecureVaultDatabaseProvider
        let account = SecureVaultModels.WebsiteAccount(title: "Example Title", username: "brindy", domain: "example.com")
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8)!)
        try database.storeWebsiteCredentials(credentials)

        let results = try database.websiteAccountsForDomain("example.com")
        XCTAssertEqual(results.count, 1)
        XCTAssertNotNil(results[0].id)
        XCTAssertEqual(account.domain, results[0].domain)
        XCTAssertEqual(account.title, results[0].title)
        XCTAssertEqual(account.username, results[0].username)
        XCTAssertNotNil(account.created)
        XCTAssertNotNil(account.lastUpdated)
    }

    func test_when_database_is_new_then_no_records() throws {
        let database = try DefaultDatabaseProvider(key: simpleL1Key) as SecureVaultDatabaseProvider
        let results = try database.websiteAccountsForDomain("example.com")
        XCTAssertTrue(results.isEmpty)
    }

    func test_when_credentials_are_deleted_then_they_are_removed_from_the_database() throws {
        let database = try DefaultDatabaseProvider(key: simpleL1Key) as SecureVaultDatabaseProvider

        let firstAccount = SecureVaultModels.WebsiteAccount(username: "brindy", domain: "example1.com")
        let firstAccountCredentials = SecureVaultModels.WebsiteCredentials(account: firstAccount, password: "password".data(using: .utf8)!)
        try database.storeWebsiteCredentials(firstAccountCredentials)

        let secondAccount = SecureVaultModels.WebsiteAccount(username: "brindy", domain: "example2.com")
        let secondAccountCredentials = SecureVaultModels.WebsiteCredentials(account: secondAccount, password: "password".data(using: .utf8)!)
        try database.storeWebsiteCredentials(secondAccountCredentials)

        XCTAssertEqual(2, try database.accounts().count)
        let storedAccount = try database.websiteAccountsForDomain("example1.com")[0]
        try database.deleteWebsiteCredentialsForAccountId(storedAccount.id!)

        let credentials = try database.websiteCredentialsForAccountId(storedAccount.id!)
        XCTAssertNil(credentials)
        XCTAssertEqual(1, try database.accounts().count)
    }

}
// swiftlint:enable force_try
