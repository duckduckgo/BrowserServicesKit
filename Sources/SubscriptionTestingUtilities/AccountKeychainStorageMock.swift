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

    enum MockAccountKeychainField: String {
        case authToken, email, externalID
    }

    public var clearAuthenticationStateCalled: Bool = false

    public var authToken: String?
    public var email: String?
    public var externalID: String?

    public var mockedAccessError: AccountKeychainAccessError?

    public init() { }

    public func getAuthToken() throws -> String? {
        try getString(forField: .authToken)
    }

    public func store(authToken: String) throws {
        try set(string: authToken, forField: .authToken)
    }

    public func getEmail() throws -> String? {
        try getString(forField: .email)
    }

    public func store(email: String?) throws {
        try set(string: email, forField: .email)
    }

    public func getExternalID() throws -> String? {
        try getString(forField: .externalID)
    }

    public func store(externalID: String?) throws {
        try set(string: externalID, forField: .externalID)
    }

    func getString(forField field: MockAccountKeychainField) throws -> String? {
        if let mockedAccessError { throw mockedAccessError }

        switch field {
        case .authToken: return authToken
        case .email: return email
        case .externalID: return externalID
        }
    }

    func set(string: String?, forField field: MockAccountKeychainField) throws {
        if let mockedAccessError { throw mockedAccessError }

        switch field {
        case .authToken: authToken = string
        case .email: email = string
        case .externalID: externalID = string
        }
    }

    public func clearAuthenticationState() throws {
        clearAuthenticationStateCalled = true

        authToken = nil
        email = nil
        externalID = nil
    }
}
