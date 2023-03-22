//
//  DDGSync.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Combine
import DDGSyncCrypto

public class DDGSync: DDGSyncing {

    enum Constants {
#if DEBUG
        public static let baseUrl = URL(string: "https://dev-sync-use.duckduckgo.com")!
#else
        public static let baseUrl = URL(string: "https://sync.duckduckgo.com")!
#endif
    }

    @Published public private(set) var isAuthenticated: Bool
    public var isAuthenticatedPublisher: AnyPublisher<Bool, Never> {
        $isAuthenticated.eraseToAnyPublisher()
    }

    public var account: SyncAccount? {
        try? dependencies.secureStore.account()
    }

    /// This is the constructor intended for use by app clients.
    public convenience init(persistence: LocalDataPersisting) {
        let dependencies = ProductionDependencies(baseUrl: Constants.baseUrl, persistence: persistence)
        self.init(persistence: persistence, dependencies: dependencies)
    }

    public func createAccount(deviceName: String, deviceType: String) async throws {
        guard try dependencies.secureStore.account() == nil else {
            throw SyncError.accountAlreadyExists
        }

        let account = try await dependencies.account.createAccount(deviceName: deviceName, deviceType: deviceType)
        try dependencies.secureStore.persistAccount(account)
        updateIsAuthenticated()
    }

    public func login(_ recoveryKey: SyncCode.RecoveryKey, deviceName: String, deviceType: String) async throws {
        guard try dependencies.secureStore.account() == nil else {
            throw SyncError.accountAlreadyExists
        }

        let result = try await dependencies.account.login(recoveryKey, deviceName: deviceName, deviceType: deviceType)
        try dependencies.secureStore.persistAccount(result.account)
        updateIsAuthenticated()
    }

    public func sender() throws -> UpdatesSending {
        return try dependencies.createUpdatesSender(persistence)
    }

    public func fetchLatest() async throws {
        try await dependencies.createUpdatesFetcher(persistence).fetch()
    }

    public func fetchEverything() async throws {
        persistence.updateBookmarksLastModified(nil)
        try await dependencies.createUpdatesFetcher(persistence).fetch()
    }
    
    public func disconnect() async throws {
        guard let deviceId = try dependencies.secureStore.account()?.deviceId else {
            throw SyncError.accountNotFound
        }
        try await disconnect(deviceId: deviceId)
    }

    public func disconnect(deviceId: String) async throws {
        guard let token = try dependencies.secureStore.account()?.token else {
            throw SyncError.noToken
        }
        try dependencies.secureStore.removeAccount()
        try await dependencies.account.logout(deviceId: deviceId, token: token)
        updateIsAuthenticated()
    }

    // MARK: -

    let persistence: LocalDataPersisting
    let dependencies: SyncDependencies

    init(persistence: LocalDataPersisting, dependencies: SyncDependencies) {
        self.persistence = persistence
        self.dependencies = dependencies
        self.isAuthenticated = (try? dependencies.secureStore.account()?.token) != nil
    }

    private func updateIsAuthenticated() {
        isAuthenticated = (try? dependencies.secureStore.account()?.token) != nil
    }
}
