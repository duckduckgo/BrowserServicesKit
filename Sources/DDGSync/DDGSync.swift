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

    public var recoveryCode: Data? {
        guard let account = try? dependencies.secureStore.account(),
            let userIdData = account.userId.data(using: .utf8) else { return nil }
        return account.primaryKey + userIdData
    }

    let persistence: LocalDataPersisting
    let dependencies: SyncDependencies

    /// This is the constructor intended for use by app clients.
    public convenience init(persistence: LocalDataPersisting) {
        let dependencies = ProductionDependencies(baseUrl: Constants.baseUrl, persistence: persistence)
        self.init(persistence: persistence, dependencies: dependencies)
    }

    /// TODO delete this - only intended for use by the CLI during dev
    public convenience init(persistence: LocalDataPersisting,
                            fileStorageUrl: URL,
                            baseUrl: URL,
                            secureStore: SecureStoring) {
        
        let dependencies = ProductionDependencies(fileStorageUrl: fileStorageUrl,
                                                  baseUrl: baseUrl,
                                                  persistence: persistence,
                                                  secureStore: secureStore)
        
        self.init(persistence: persistence, dependencies: dependencies)
    }

    init(persistence: LocalDataPersisting, dependencies: SyncDependencies) {
        self.persistence = persistence
        self.dependencies = dependencies
        self.isAuthenticated = (try? dependencies.secureStore.account()?.token) != nil
    }
    
    public func createAccount(deviceName: String) async throws {
        guard try dependencies.secureStore.account() == nil else {
            throw SyncError.accountAlreadyExists
        }

        let account = try await dependencies.account.createAccount(deviceName: deviceName)
        try dependencies.secureStore.persistAccount(account)
        updateIsAuthenticated()
    }

    public func login(recoveryKey: Data, deviceName: String) async throws {
        guard try dependencies.secureStore.account() == nil else {
            throw SyncError.accountAlreadyExists
        }

        let result = try await dependencies.account.login(recoveryKey: recoveryKey, deviceName: deviceName)
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
        try await dependencies.account.logout(deviceId: deviceId, token: token)
        try dependencies.secureStore.removeAccount()
        updateIsAuthenticated()
    }

    private func updateIsAuthenticated() {
        isAuthenticated = (try? dependencies.secureStore.account()?.token) != nil
    }
}
