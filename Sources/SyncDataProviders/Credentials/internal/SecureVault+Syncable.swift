//
//  SecureVault+Syncable.swift
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

import BrowserServicesKit
import DDGSync
import GRDB

extension SecureVault {

    func deduplicatedCredentials(
        in database: Database,
        with syncable: Syncable,
        decryptedUsing decrypt: (String) throws -> String
    ) throws -> SecureVaultModels.SyncableCredentials? {

        guard !syncable.isDeleted else {
            return nil
        }

        let domain = try syncable.encryptedDomain.flatMap(decrypt)
        let username = try syncable.encryptedUsername.flatMap(decrypt)
        let password = try syncable.encryptedPassword.flatMap(decrypt)
        let notes = try syncable.encryptedNotes.flatMap(decrypt)

        let accountAlias = TableAlias()
        let credentialsAlias = TableAlias()
        let conditions = [
            accountAlias[SecureVaultModels.WebsiteAccount.Columns.domain] == domain,
            accountAlias[SecureVaultModels.WebsiteAccount.Columns.username] == username,
            accountAlias[SecureVaultModels.WebsiteAccount.Columns.notes] == notes
        ]
        let syncableCredentials = try SecureVaultModels.SyncableCredentialsRecord
            .including(optional: SecureVaultModels.SyncableCredentialsRecord.account.aliased(accountAlias))
            .including(optional: SecureVaultModels.SyncableCredentialsRecord.credentials.aliased(credentialsAlias))
            .filter(conditions.joined(operator: .and))
            .asRequest(of: SecureVaultModels.SyncableCredentials.self)
            .fetchAll(database)

        guard !syncableCredentials.isEmpty else {
            return nil
        }

        let key = try getEncryptionKey()

        if let password, let passwordData = password.data(using: .utf8) {
            return try syncableCredentials.first(where: { credentials in
                let decryptedPassword = try credentials.credentialsRecord?.password.flatMap { try self.decrypt($0, using: key) }
                return decryptedPassword == passwordData
            })
        }
        return syncableCredentials.first(where: { $0.credentialsRecord?.password == nil })
    }

}
