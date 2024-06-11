//
//  UserDefaults+dnsSettings.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
    final class StorableDNSSettings: NSObject, Codable {
        let usesCustomDNS: Bool
        let dnsServers: [String]

        init(usesCustomDNS: Bool = false, dnsServers: [String] = []) {
            self.usesCustomDNS = usesCustomDNS
            self.dnsServers = dnsServers
        }
    }

    private var dnsSettingKey: String {
        "dnsSetting"
    }

    private static func dnsSettingsFromStorageValue(_ value: StorableDNSSettings) -> NetworkProtectionDNSSettings {
        guard value.usesCustomDNS else { return .default }
        return .custom(value.dnsServers)
    }

    @objc
    dynamic var dnsSettingStorageValue: StorableDNSSettings {
        get {
            guard let data = data(forKey: dnsSettingKey) else { return StorableDNSSettings() }
            return (try? JSONDecoder().decode(StorableDNSSettings.self, from: data)) ?? StorableDNSSettings()
        }

        set {
            if let data = try? JSONEncoder().encode(newValue) {
                set(data, forKey: dnsSettingKey)
            }
        }
    }

    var dnsSettings: NetworkProtectionDNSSettings {
        get {
            Self.dnsSettingsFromStorageValue(dnsSettingStorageValue)
        }

        set {
            switch newValue {
            case .default:
                dnsSettingStorageValue = StorableDNSSettings()
            case .custom(let dnsServers):
                dnsSettingStorageValue = StorableDNSSettings(usesCustomDNS: true, dnsServers: dnsServers)
            }
        }
    }

    var dnsSettingsPublisher: AnyPublisher<NetworkProtectionDNSSettings, Never> {
        publisher(for: \.dnsSettingStorageValue)
            .map(Self.dnsSettingsFromStorageValue(_:))
            .eraseToAnyPublisher()
    }

    func resetDNSSettings() {
        dnsSettings = .default
    }
}
