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

    func signIn(username: String, token: String) throws
    func signOut() throws

    var userDidToggleEmailProtectionPublisher: AnyPublisher<Void, Never> { get }
}

extension SettingsProvider.Setting {
    static let emailProtectionGeneration = SettingsProvider.Setting(key: "email_protection_generation")
}

class EmailProtectionSyncHandler: SettingsSyncHandling {

    struct Payload: Codable {
        let username: String
        let personalAccessToken: String
    }

    let setting: SettingsProvider.Setting = .emailProtectionGeneration
    weak var delegate: SettingsSyncHandlingDelegate?

    func getValue() throws -> String? {
        guard let user = try emailManager.getUsername() else {
            return nil
        }
        guard let token = try emailManager.getToken() else {
            throw SyncError.emailProtectionUsernamePresentButTokenMissing
        }
        let data = try JSONEncoder.snakeCaseKeys.encode(Payload(username: user, personalAccessToken: token))
        return String(bytes: data, encoding: .utf8)
    }

    func setValue(_ value: String?) throws {
        guard let value, let valueData = value.data(using: .utf8) else {
            try emailManager.signOut()
            return
        }

        let payload = try JSONDecoder.snakeCaseKeys.decode(Payload.self, from: valueData)
        try emailManager.signIn(username: payload.username, token: payload.personalAccessToken)
    }

    init(emailManager: EmailManagerSyncSupporting) {
        self.emailManager = emailManager

        emailProtectionStatusDidChangeCancellable = self.emailManager.userDidToggleEmailProtectionPublisher
            .sink { [weak self] in
                guard let self else {
                    return
                }
                assert(self.delegate != nil, "delegate has not been set for \(type(of: self))")
                self.delegate?.syncHandlerDidUpdateSettingValue(self)
            }
    }

    private let emailManager: EmailManagerSyncSupporting
    private var emailProtectionStatusDidChangeCancellable: AnyCancellable?
}
