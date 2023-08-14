//
//  DuckAddressAdapter.swift
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

import Foundation
import BrowserServicesKit
import Combine
import DDGSync
import Persistence

class DuckAddressAdapter: SettingsSyncAdapter {

    struct Payload: Codable {
        let user: String
        let token: String
    }

    init(emailManager: EmailManager, metadataDatabase: CoreDataDatabase) {
        self.emailManager = emailManager
        self.metadataDatabase = metadataDatabase

        emailProtectionStatusDidChangeCancellable = Publishers.Merge(
            NotificationCenter.default.publisher(for: .emailDidSignIn),
            NotificationCenter.default.publisher(for: .emailDidSignOut)
        )
        .sink { [weak self] notification in
            if let object = notification.object as? AnyObject, object !== emailManager {
                self?.updateDuckAddressTimestamp()
            }
        }
    }

    func getValue() throws -> String? {
        guard let user = emailManager.userEmail else {
            return nil
        }
        guard let token = emailManager.token else {
            throw SyncError.duckAddressTokenMissing
        }
        return "{\"user\":\"\(user)\",\"token\":\"\(token)\"}"
    }

    func setValue(_ value: String?) throws {
        guard let value, let valueData = value.data(using: .utf8) else {
            emailManager.signOut()
            return
        }

        let payload = try JSONDecoder().decode(Payload.self, from: valueData)
        emailManager.storeToken(payload.token, username: emailManager.aliasFor(payload.user), cohort: nil)
    }

    private func updateDuckAddressTimestamp() {
        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            do {
                SyncableSettingsMetadataUtils.setLastModified(Date(), forSettingWith: SettingsProvider.Setting.duckAddress.rawValue, in: context)
                try context.save()
            } catch {
                // todo: error
                print("ERROR in \(#function): \(error.localizedDescription)")
            }
        }
    }

    private let emailManager: EmailManager
    private let metadataDatabase: CoreDataDatabase
    private var emailProtectionStatusDidChangeCancellable: AnyCancellable?
}
