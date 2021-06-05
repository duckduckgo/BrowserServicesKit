//
//  SecureVaultModels.swift
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

/// The models used by the secure vault.
/// 
/// Future models include:
///  * Generated Password - a password generated for a site, but not used yet
///  * Duck Address - a duck address used on a partcular site
public struct SecureVaultModels {

    /// A username and password was saved for a given site.  Password is stored seperately so that
    ///  it can be queried independently.
    public struct WebsiteCredentials {

        public var account: WebsiteAccount
        public var password: Data

        public init(account: WebsiteAccount, password: Data) {
            self.account = account
            self.password = password
        }

    }

    /// The username associated with a domain.
    public struct WebsiteAccount {

        public var id: Int64?
        public var username: String
        public let domain: String
        public let created: Date
        public let lastUpdated: Date

        public init(username: String, domain: String) {
            self.id = nil
            self.username = username
            self.domain = domain
            self.created = Date()
            self.lastUpdated = self.created
        }

        init(id: Int64, username: String, domain: String, created: Date, lastUpdated: Date) {
            self.id = id
            self.username = username
            self.domain = domain
            self.created = created
            self.lastUpdated = lastUpdated
        }

    }

}
