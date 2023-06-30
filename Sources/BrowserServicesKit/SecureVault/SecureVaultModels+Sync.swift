//
//  SecureVaultModels+Sync.swift
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

import Common
import Foundation
import GRDB

public protocol SecureVaultSyncable {
    var id: String { get set }
    var objectId: Int64? { get }
    var lastModified: Date? { get set }
}

public enum SecureVaultSyncableColumns: String, ColumnExpression {
    case id, objectId, lastModified
}

extension SecureVaultModels {

    public struct WebsiteAccountSyncMetadata: SecureVaultSyncable {

        public var id: String
        public var credential: WebsiteCredentials?
        public var lastModified: Date?

        public var objectId: Int64? {
            credential?.account.id.flatMap(Int64.init)
        }

        public init(id: String = UUID().uuidString, credential: WebsiteCredentials?, lastModified: Date? = Date()) {
            self.id = id
            self.credential = credential
            self.lastModified = lastModified
        }
    }
}

extension SecureVaultModels.WebsiteAccountSyncMetadata: PersistableRecord {

    public typealias Columns = SecureVaultSyncableColumns

    public func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.objectId] = credential?.account.id
        container[Columns.lastModified] = lastModified
    }

    public static var databaseTableName: String = "website_accounts_sync_metadata"
}
