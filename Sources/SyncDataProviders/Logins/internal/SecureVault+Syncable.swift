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

    func deduplicatedCredential(
        in database: Database,
        with syncable: Syncable,
        decryptedUsing decrypt: (String) throws -> String
    ) throws -> SecureVaultModels.WebsiteAccountSyncMetadata? {

        guard !syncable.isDeleted else {
            return nil
        }

        let domain = try decrypt(syncable.encryptedDomain ?? "")
        let username = try decrypt(syncable.encryptedUsername ?? "")

        let accountIdString = try accountsForDomain(domain, in: database).first(where: { $0.username == username })?.id

        guard let accountIdString, let accountId = Int64(accountIdString) else {
            return nil
        }

        return try websiteCredentialsMetadataForAccountId(accountId, in: database)
    }

}
