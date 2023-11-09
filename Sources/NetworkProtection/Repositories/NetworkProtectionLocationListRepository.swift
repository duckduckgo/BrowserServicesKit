//
//  NetworkProtectionLocationListRepository.swift
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

public protocol NetworkProtectionLocationListRepository {
    func fetchLocationList() async throws -> [NetworkProtectionLocation]
}

final public class NetworkProtectionLocationListCompositeRepository: NetworkProtectionLocationListRepository {
    @MainActor private static var locationList: [NetworkProtectionLocation] = []
    private let client: NetworkProtectionClient
    private let tokenStore: NetworkProtectionTokenStore

    convenience public init(tokenStore: NetworkProtectionTokenStore) {
        self.init(client: NetworkProtectionBackendClient(), tokenStore: tokenStore)
    }

    init(client: NetworkProtectionClient, tokenStore: NetworkProtectionTokenStore) {
        self.client = client
        self.tokenStore = tokenStore
    }

    @MainActor
    public func fetchLocationList() async throws -> [NetworkProtectionLocation] {
        guard Self.locationList.isEmpty else {
            return Self.locationList
        }
        do {
            guard let authToken = try tokenStore.fetchToken() else {
                throw NetworkProtectionError.noAuthTokenFound
            }
            Self.locationList = try await client.getLocations(authToken: authToken).get()
        } catch let error as NetworkProtectionErrorConvertible {
            throw error.networkProtectionError
        } catch {
            throw NetworkProtectionError.unhandledError(function: #function, line: #line, error: error)
        }
        return Self.locationList
    }
}
