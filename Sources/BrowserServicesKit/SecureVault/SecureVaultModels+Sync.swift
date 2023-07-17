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
    var uuid: String { get set }
    var objectId: Int64? { get }
    var lastModified: Date? { get set }
}

public enum SecureVaultSyncableColumns: String, ColumnExpression {
    case id, uuid, objectId, lastModified
}

extension SecureVaultModels {

    public struct SyncableWebsiteCredential: SecureVaultSyncable, TableRecord, FetchableRecord, PersistableRecord, Decodable {
        public typealias Columns = SecureVaultSyncableColumns
        public static var databaseTableName: String = "website_accounts_sync_metadata"

        public static let accountForeignKey = ForeignKey([Columns.objectId])
        public static let credentialsForeignKey = ForeignKey([Columns.objectId])
        public static let account = belongsTo(SecureVaultModels.WebsiteAccount.self, key: "account", using: accountForeignKey)
        public static let credentials = belongsTo(SecureVaultModels.RawWebsiteCredentials.self, key: "rawCredentials", using: credentialsForeignKey)

        public var id: Int64?
        public var uuid: String
        public var objectId: Int64?
        public var lastModified: Date?

        public init(row: Row) throws {
            id = row[Columns.id]
            uuid = row[Columns.uuid]
            objectId = row[Columns.objectId]
            lastModified = row[Columns.lastModified]
        }

        public func encode(to container: inout PersistenceContainer) {
            container[Columns.id] = id
            container[Columns.uuid] = uuid
            container[Columns.objectId] = objectId
            container[Columns.lastModified] = lastModified
        }

        public init(uuid: String = UUID().uuidString, objectId: Int64?, lastModified: Date? = Date()) {
            self.uuid = uuid
            self.objectId = objectId
            self.lastModified = lastModified
        }
    }

    public struct SyncableWebsiteCredentialInfo: FetchableRecord, Decodable {
        public var metadata: SyncableWebsiteCredential
        public var account: WebsiteAccount? {
            didSet {
                metadata.objectId = account?.id.flatMap(Int64.init)
            }
        }
        public var rawCredentials: RawWebsiteCredentials? {
            didSet {
                metadata.objectId = account?.id.flatMap(Int64.init)
            }
        }

        public var credentials: WebsiteCredentials? {
            get {
                guard let account else {
                    return nil
                }
                return .init(account: account, password: rawCredentials?.password)
            }
            set {
                rawCredentials = newValue.flatMap { RawWebsiteCredentials(credentials: $0) }
                account = newValue?.account
            }
        }

        public init(uuid: String = UUID().uuidString, credentials: WebsiteCredentials?, lastModified: Date? = Date()) {
            metadata = .init(uuid: uuid, objectId: credentials?.account.id.flatMap(Int64.init), lastModified: lastModified)
            self.credentials = credentials
        }
    }
}
