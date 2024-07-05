//
//  AccountKeychainStorageMock.swift
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

import Foundation
import Subscription

public class AccountKeychainStorageMock: AccountStoring {
    public var authToken: String?
    public var accessToken: String?
    public var email: String?
    public var externalID: String?

    public init(authToken: String? = nil, accessToken: String? = nil, email: String? = nil, externalID: String? = nil) {
        self.authToken = authToken
        self.accessToken = accessToken
        self.email = email
        self.externalID = externalID
    }

    public func getAuthToken() throws -> String? {
        authToken
    }

    public func store(authToken: String) throws {
        self.authToken = authToken
    }

    public func getAccessToken() throws -> String? {
        accessToken
    }

    public func store(accessToken: String) throws {
        self.accessToken = accessToken
    }

    public func getEmail() throws -> String? {
        email
    }

    public func store(email: String?) throws {
        self.email = email
    }

    public func getExternalID() throws -> String? {
        externalID
    }

    public func store(externalID: String?) throws {
        self.externalID = externalID
    }

    public func clearAuthenticationState() throws {
        authToken = nil
        accessToken = nil
        email = nil
        externalID = nil
    }
}
