//
//  RegistrationKeyManager.swift
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

/// This is the main interface for interacting with registration keys accross the codebase.
///
final class RegistrationKeyManager {
    typealias RekeyHandler = () async throws -> Void

    let keyStore: NetworkProtectionKeychainKeyStore
    private let settings: VPNSettings
    private let rekeyHandler: RekeyHandler

    private let debugEvents: EventMapping<NetworkProtectionError>?
    private let providerEvents: EventMapping<PacketTunnelProvider.Event>

    init(keychainType: KeychainType,
         settings: VPNSettings,
         providerEvents: EventMapping<PacketTunnelProvider.Event>,
         debugEvents: EventMapping<NetworkProtectionError>?,
         onRekey rekeyHandler: @escaping RekeyHandler) {

        self.settings = settings
        self.rekeyHandler = rekeyHandler
        self.providerEvents = providerEvents
        self.debugEvents = debugEvents

        keyStore = NetworkProtectionKeychainKeyStore(keychainType: keychainType,
                                                     errorEvents: debugEvents)
    }

    func resetAllState() {
        resetRegistrationKey()
    }

    private func resetRegistrationKey() {
        os_log("Resetting the current registration key", log: .networkProtectionKeyManagement)
        keyStore.resetCurrentKeyPair()
    }

    private var isKeyExpired: Bool {
        keyStore.currentKeyPair().expirationDate <= Date()
    }

    func rekeyIfExpired() async {
        guard isKeyExpired else {
            return
        }

        await rekey()
    }

    func rekey() async {
        providerEvents.fire(.userBecameActive)

        // Experimental option to disable rekeying.
        guard !settings.disableRekeying else {
            return
        }

        os_log("Rekeying...", log: .networkProtectionKeyManagement)

        providerEvents.fire(.rekeyCompleted)
        resetRegistrationKey()

        do {
            try await rekeyHandler()
        } catch {
            os_log("Rekey attempt failed.  This is not an error if you're using debug Key Management options: %{public}@", log: .networkProtectionKeyManagement, type: .error, String(describing: error))
        }
    }

    func setKeyValidity(_ interval: TimeInterval?) {
        if let interval {
            let firstExpirationDate = Date().addingTimeInterval(interval)

            os_log("Setting key validity interval to %{public}@ seconds (next expiration date %{public}@)",
                   log: .networkProtectionKeyManagement,
                   String(describing: interval),
                   String(describing: firstExpirationDate))

            settings.registrationKeyValidity = .custom(interval)
        } else {
            os_log("Resetting key validity interval",
                   log: .networkProtectionKeyManagement)

            settings.registrationKeyValidity = .automatic
        }

        keyStore.setValidityInterval(interval)
    }
}
