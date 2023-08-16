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

public protocol EmailProtectionSyncSupporting: AnyObject {
    var userEmail: String? { get }
    var token: String? { get }
    var userDidToggleEmailProtectionPublisher: AnyPublisher<Void, Never> { get }

    func signIn(userEmail: String, token: String)
    func signOut()

}

class EmailProtectionSettingsAdapter: SettingsSyncAdapter {

    struct Payload: Codable {
        let mainDuckAddress: String
        let personalAccessToken: String
    }

    init(emailManager: EmailProtectionSyncSupporting, metadataDatabase: CoreDataDatabase) {
        self.emailManager = emailManager
        self.metadataDatabase = metadataDatabase

        emailProtectionStatusDidChangeCancellable = self.emailManager.userDidToggleEmailProtectionPublisher
            .sink { [weak self] in
                self?.updateDuckAddressTimestamp()
            }
    }

    func getValue() throws -> String? {
        guard let user = emailManager.userEmail else {
            return nil
        }
        guard let token = emailManager.token else {
            throw SyncError.duckAddressTokenMissing
        }
        let data = try JSONEncoder.snakeCaseKeys.encode(Payload(mainDuckAddress: user, personalAccessToken: token))
        return String(bytes: data, encoding: .utf8)
    }

    func setValue(_ value: String?) throws {
        guard let value, let valueData = value.data(using: .utf8) else {
            emailManager.signOut()
            return
        }

        let payload = try JSONDecoder.snakeCaseKeys.decode(Payload.self, from: valueData)
        emailManager.signIn(userEmail: payload.mainDuckAddress, token: payload.personalAccessToken)
    }

    private func updateDuckAddressTimestamp() {
        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            do {
                try SyncableSettingsMetadataUtils.setLastModified(
                    Date(),
                    forSettingWithKey: SettingsProvider.Setting.emailProtectionGeneration.rawValue,
                    in: context
                )
                try context.save()
            } catch {
                // todo: error
                print("ERROR in \(#function): \(error.localizedDescription)")
            }
        }
    }

    private let emailManager: EmailProtectionSyncSupporting
    private let metadataDatabase: CoreDataDatabase
    private var emailProtectionStatusDidChangeCancellable: AnyCancellable?
}
