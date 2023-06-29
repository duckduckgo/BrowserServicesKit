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

extension SecureVaultModels {

    public struct WebsiteAccountSyncMetadata {
        public var id: String
        public var accountId: String?
        public var lastModified: Date?
    }
}

extension SecureVaultModels.WebsiteAccountSyncMetadata: PersistableRecord, FetchableRecord {

    enum Columns: String, ColumnExpression {
        case id, accountId, lastModified
    }

    public init(row: Row) {
        id = row[Columns.id]
        accountId = row[Columns.accountId]
        lastModified = row[Columns.lastModified]
    }

    public func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.accountId] = accountId
        container[Columns.lastModified] = Date()
    }

    public static var databaseTableName: String = "website_accounts_sync_metadata"
}
