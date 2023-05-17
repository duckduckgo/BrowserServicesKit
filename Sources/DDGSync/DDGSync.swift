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
import Common
import os.log

public class DDGSync: DDGSyncing {

    public static let bundle = Bundle.module

    enum Constants {
        //#if DEBUG
        public static let baseUrl = URL(string: "https://dev-sync-use.duckduckgo.com")!
        //#else
        //        public static let baseUrl = URL(string: "https://sync.duckduckgo.com")!
        //#endif
    }

    @Published public private(set) var authState: SyncAuthState
    public var authStatePublisher: AnyPublisher<SyncAuthState, Never> {
        $authState.eraseToAnyPublisher()
    }

    public var account: SyncAccount? {
        try? dependencies.secureStore.account()
    }

    public var scheduler: Scheduling {
        dependencies.scheduler
    }

    public var isInProgressPublisher: AnyPublisher<Bool, Never> {
        dependencies.syncQueue.isSyncInProgressPublisher
    }

    /// This is the constructor intended for use by app clients.
    public convenience init(dataProviders: [DataProviding], log: @escaping @autoclosure () -> OSLog = .disabled) {
        let dependencies = ProductionDependencies(baseUrl: Constants.baseUrl, dataProviders: dataProviders, log: log())
        self.init(dependencies: dependencies)
    }

    public func createAccount(deviceName: String, deviceType: String) async throws {
        guard try dependencies.secureStore.account() == nil else {
            throw SyncError.accountAlreadyExists
        }

        let account = try await dependencies.account.createAccount(deviceName: deviceName, deviceType: deviceType)
        try dependencies.secureStore.persistAccount(account)
        updateAuthState()
    }

    public func login(_ recoveryKey: SyncCode.RecoveryKey, deviceName: String, deviceType: String) async throws {
        guard try dependencies.secureStore.account() == nil else {
            throw SyncError.accountAlreadyExists
        }

        let result = try await dependencies.account.login(recoveryKey, deviceName: deviceName, deviceType: deviceType)
        try dependencies.secureStore.persistAccount(result.account)
        updateAuthState()
    }

    public func remoteConnect() throws -> RemoteConnecting {
        guard try dependencies.secureStore.account() == nil else {
            throw SyncError.accountAlreadyExists
        }
        let info = try dependencies.crypter.prepareForConnect()
        return try dependencies.createRemoteConnector(info)
    }

    public func transmitRecoveryKey(_ connectCode: SyncCode.ConnectCode) async throws {
        guard try dependencies.secureStore.account() != nil else {
            throw SyncError.accountNotFound
        }

        do {
            try await dependencies.createRecoveryKeyTransmitter().send(connectCode)
        } catch {
            try handleUnauthenticated(error)
        }
    }

    public func disconnect() async throws {
        guard let deviceId = try dependencies.secureStore.account()?.deviceId else {
            throw SyncError.accountNotFound
        }
        do {
            try await disconnect(deviceId: deviceId)
            try dependencies.secureStore.removeAccount()
        } catch {
            try handleUnauthenticated(error)
        }
        updateAuthState()
    }

    public func disconnect(deviceId: String) async throws {
        guard let token = try dependencies.secureStore.account()?.token else {
            throw SyncError.noToken
        }
        do {
            try await dependencies.account.logout(deviceId: deviceId, token: token)
        } catch {
            try handleUnauthenticated(error)
        }
    }

    public func fetchDevices() async throws -> [RegisteredDevice] {
        guard let account = try dependencies.secureStore.account() else {
            throw SyncError.accountNotFound
        }

        do {
            return try await dependencies.account.fetchDevicesForAccount(account)
        } catch {
            try handleUnauthenticated(error)
        }

        return []
    }

    public func updateDeviceName(_ name: String) async throws -> [RegisteredDevice] {
        guard let account = try dependencies.secureStore.account() else {
            throw SyncError.accountNotFound
        }

        do {
            let result = try await dependencies.account.refreshToken(account, deviceName: name)
            try dependencies.secureStore.persistAccount(result.account)
            return result.devices
        } catch {
            try handleUnauthenticated(error)
        }

        return []
    }

    public func deleteAccount() async throws {
        guard let account = try dependencies.secureStore.account() else {
            throw SyncError.accountNotFound
        }

        do {
            try await dependencies.account.deleteAccount(account)
            try dependencies.secureStore.removeAccount()
            updateAuthState()
        } catch {
            try handleUnauthenticated(error)
        }
    }

    // MARK: -

    let dependencies: SyncDependencies

    init(dependencies: SyncDependencies) {
        self.dependencies = dependencies
        self.authState = .inactive

        // do not start sync upon initialization
        updateAuthState(startSyncIfNeeded: false)
    }

    private func updateAuthState(startSyncIfNeeded: Bool = true) {
        let previousState = authState
        authState = (try? dependencies.secureStore.account()?.state) ?? .inactive

        if previousState == .inactive && authState != .inactive {
            startSyncCancellable = dependencies.scheduler.startSyncPublisher
                .sink { [weak self] in
                    guard let self else {
                        return
                    }
                    Task {
                        if self.authState == .active {
                            await self.dependencies.syncQueue.startSync()
                        } else {
                            await self.dependencies.syncQueue.setUpAndStartFirstSync()
                        }
                    }
                }

            syncDidFinishCancellable = dependencies.syncQueue.syncDidFinishPublisher
                .sink { [weak self] result in
                    if case .success = result {
                        self?.updateAuthState()
                    }
                }

            if startSyncIfNeeded {
                Task {
                    await dependencies.syncQueue.setUpAndStartFirstSync()
                    dependencies.scheduler.isEnabled = true
                }
            } else {
                dependencies.scheduler.isEnabled = true
            }

        } else if authState == .inactive {
            dependencies.scheduler.isEnabled = false
            startSyncCancellable?.cancel()
            syncDidFinishCancellable?.cancel()
        }
    }

    private func handleUnauthenticated(_ error: Error) throws {
        guard let syncError = error as? SyncError,
              case .unexpectedStatusCode(let statusCode) = syncError,
              statusCode == 401 else {
            throw error
        }

        do {
            try self.dependencies.secureStore.removeAccount()
        } catch {
            // We should probably log this, maybe fire a pixel
            print(error)
        }
        updateAuthState()
    }

    private var startSyncCancellable: AnyCancellable?
    private var syncDidFinishCancellable: AnyCancellable?
}
