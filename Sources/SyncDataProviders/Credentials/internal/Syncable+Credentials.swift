//
//  Syncable+Credentials.swift
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
import Foundation

extension Syncable {

    var encryptedDomain: String? {
        payload["domain"] as? String
    }

    var encryptedUsername: String? {
        payload["username"] as? String
    }

    var encryptedPassword: String? {
        payload["password"] as? String
    }

    var encryptedNotes: String? {
        payload["notes"] as? String
    }

    init(metadata: SecureVaultModels.SyncableWebsiteCredentialsInfo, encryptedUsing encrypt: (String) throws -> String) throws {
        var payload: [String: Any] = [:]

        payload["id"] = metadata.metadata.uuid

        guard let credential = metadata.credentials else {
            payload["deleted"] = ""
            self.init(jsonObject: payload)
            return
        }

        print("Syncable init \(metadata.metadata.uuid)")
        if let title = credential.account.title {
            payload["title"] = try encrypt(title)
        }
        if let domain = credential.account.domain {
            payload["domain"] = try encrypt(domain)
        }
        if let username = credential.account.username {
            payload["username"] = try encrypt(username)
        }
        if let notes = credential.account.notes {
            payload["notes"] = try encrypt(notes)
        }

        if let passwordData = credential.password, let password = String(data: passwordData, encoding: .utf8) {
            payload["password"] = try encrypt(password)
        }

        if let modifiedAt = metadata.metadata.lastModified {
            payload["client_last_modified"] = Self.dateFormatter.string(from: modifiedAt)
        }
        self.init(jsonObject: payload)
    }

    private static var dateFormatter: ISO8601DateFormatter {
        ISO8601DateFormatter()
    }
}
