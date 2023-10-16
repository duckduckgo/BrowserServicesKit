//
//  UserDefaults+registrationKeyValidity.swift
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

import Combine
import Foundation

extension UserDefaults {
    private var registrationKeyValidityKey: String {
        "networkProtectionSettingRegistrationKeyValidityRawValue"
    }

    @objc
    dynamic var networkProtectionSettingRegistrationKeyValidityRawValue: NSNumber? {
        get {
            value(forKey: registrationKeyValidityKey) as? NSNumber
        }

        set {
            set(newValue, forKey: registrationKeyValidityKey)
        }
    }

    private func registrationKeyValidityFromRawValue(_ rawValue: NSNumber?) -> TunnelSettings.RegistrationKeyValidity {
        guard let timeInterval = networkProtectionSettingRegistrationKeyValidityRawValue?.doubleValue else {
            return .automatic
        }

        return .custom(timeInterval)
    }

    var networkProtectionSettingRegistrationKeyValidity: TunnelSettings.RegistrationKeyValidity {
        get {
            registrationKeyValidityFromRawValue(networkProtectionSettingRegistrationKeyValidityRawValue)
        }

        set {
            switch newValue {
            case .automatic:
                networkProtectionSettingRegistrationKeyValidityRawValue = nil
            case .custom(let timeInterval):
                networkProtectionSettingRegistrationKeyValidityRawValue = NSNumber(value: timeInterval)
            }
        }
    }

    var networkProtectionSettingRegistrationKeyValidityPublisher: AnyPublisher<TunnelSettings.RegistrationKeyValidity, Never> {
        let registrationKeyValidityFromRawValue = self.registrationKeyValidityFromRawValue

        return publisher(for: \.networkProtectionSettingRegistrationKeyValidityRawValue).map { serverName in
            registrationKeyValidityFromRawValue(serverName)
        }.eraseToAnyPublisher()
    }

    func resetNetworkProtectionSettingRegistrationKeyValidity() {
        networkProtectionSettingRegistrationKeyValidityRawValue = nil
    }
}

