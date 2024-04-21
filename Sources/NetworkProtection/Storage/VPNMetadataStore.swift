//
//  VPNMetadataStore.swift
//  DuckDuckGo
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

import Foundation

public struct VPNMetadata: Codable {
    var lastWireGuardAdapterError: String? = nil
    var lastWireGuardAdapterTunnelInterface: String? = nil
}

public protocol VPNMetadataStore {
    func getMetadata() throws -> VPNMetadata
    func setValue<T>(_ value: T, for keyPath: WritableKeyPath<VPNMetadata, T>) throws
}

public struct VPNMetadataUserDefaultsStore: VPNMetadataStore {

    private enum Constants {
        static let metadataKey = "vpn.metadata"
    }

    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func setValue<T>(_ value: T, for keyPath: WritableKeyPath<VPNMetadata, T>) throws {
        var metadata = try self.getMetadata()
        metadata[keyPath: keyPath] = value

        userDefaults.set(value, forKey: Constants.metadataKey)

        try write(metadata: metadata)
    }

    public func getMetadata() throws -> VPNMetadata {
        return try readMetadata() ?? VPNMetadata()
    }

    // MARK: - Private

    private func readMetadata() throws -> VPNMetadata? {
        guard let data = userDefaults.data(forKey: Constants.metadataKey) else {
            return nil
        }

        return try self.decoder.decode(VPNMetadata.self, from: data)
    }

    private func write(metadata: VPNMetadata) throws {
        let encodedData = try self.encoder.encode(metadata)
        userDefaults.set(encodedData, forKey: Constants.metadataKey)
    }

}
