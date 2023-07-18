//
//  CredentialsDatabaseCleanerTests.swift
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

import XCTest
import Common
import GRDB
@testable import BrowserServicesKit

final class MockEventMapper: EventMapping<CredentialsCleanupError> {
    static var errors: [Error] = []

    public init() {
        super.init { event, _, _, _ in
            Self.errors.append(event.cleanupError)
        }
    }

    deinit {
        Self.errors = []
    }

    override init(mapping: @escaping EventMapping<CredentialsCleanupError>.Mapping) {
        fatalError("Use init()")
    }
}

//final class CredentialsDatabaseCleanerTests: XCTestCase {
//    var secureVaultFactory: SecureVaultFactory!
//    var location: URL!
//    var databaseCleaner: CredentialsDatabaseCleaner!
//    var eventMapper: MockEventMapper!
//
//}
