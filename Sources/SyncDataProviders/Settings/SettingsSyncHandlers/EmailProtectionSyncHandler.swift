//
//  EmailProtectionSyncHandler.swift
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

public protocol EmailManagerSyncSupporting: AnyObject {
    func getUsername() throws -> String?
    func getToken() throws -> String?

    func signIn(userEmail: String, token: String) throws
    func signOut() throws

    var userDidToggleEmailProtectionPublisher: AnyPublisher<Void, Never> { get }
}

extension SettingsProvider.Setting {
    static let emailProtectionGeneration = SettingsProvider.Setting(key: "email_protection_generation")
}

class EmailProtectionSyncHandler: SettingsSyncHandling {

    struct Payload: Codable {
        let mainDuckAddress: String
        let personalAccessToken: String
    }

    let setting: SettingsProvider.Setting = .emailProtectionGeneration

    let shouldApplyRemoteDeleteOnInitialSync: Bool = false

    let errorPublisher: AnyPublisher<Error, Never>

    func getValue() throws -> String? {
        guard let user = try emailManager.getUsername() else {
            return nil
        }
        guard let token = try emailManager.getToken() else {
            throw SyncError.emailProtectionUsernamePresentButTokenMissing
        }
        let data = try JSONEncoder.snakeCaseKeys.encode(Payload(mainDuckAddress: user, personalAccessToken: token))
        return String(bytes: data, encoding: .utf8)
    }

    func setValue(_ value: String?) throws {
        guard let value, let valueData = value.data(using: .utf8) else {
            try emailManager.signOut()
            return
        }

        let payload = try JSONDecoder.snakeCaseKeys.decode(Payload.self, from: valueData)
        try emailManager.signIn(userEmail: payload.mainDuckAddress, token: payload.personalAccessToken)
    }

    init(emailManager: EmailManagerSyncSupporting, metadataDatabase: CoreDataDatabase) {
        self.emailManager = emailManager
        self.metadataDatabase = metadataDatabase
        errorPublisher = errorSubject.eraseToAnyPublisher()

        emailProtectionStatusDidChangeCancellable = self.emailManager.userDidToggleEmailProtectionPublisher
            .sink { [weak self] in
                self?.updateMetadataTimestamp()
            }
    }

    private func updateMetadataTimestamp() {
        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            do {
                try SyncableSettingsMetadataUtils.setLastModified(Date(), forSettingWithKey: setting.key, in: context)
                try context.save()
            } catch {
                errorSubject.send(SettingsSyncMetadataSaveError(underlyingError: error))
            }
        }
    }

    private let emailManager: EmailManagerSyncSupporting
    private let metadataDatabase: CoreDataDatabase
    private var emailProtectionStatusDidChangeCancellable: AnyCancellable?
    private let errorSubject = PassthroughSubject<Error, Never>()
}
