//
//  Engine.swift
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
import Combine

/**
 * Internal interface for sync engine.
 */
protocol EngineProtocol {
    /// Used for passing data to sync
    var dataProviders: [DataProviding] { get }
    /// Called to start sync
    func setUpAndStartFirstSync() async
    /// Called to start sync
    func startSync() async
    /// Emits events when sync each operation ends
    var syncDidFinishPublisher: AnyPublisher<Result<Void, Error>, Never> { get }
}

class Engine: EngineProtocol {

    let dataProviders: [DataProviding]
    let storage: SecureStoring
    let syncDidFinishPublisher: AnyPublisher<Result<Void, Error>, Never>
    let syncQueue: SyncQueue

    init(
        dataProviders: [DataProviding],
        storage: SecureStoring,
        crypter: Crypting,
        api: RemoteAPIRequestCreating,
        endpoints: Endpoints
    ) {
        self.dataProviders = dataProviders
        self.storage = storage
        let requestMaker = SyncRequestMaker(storage: storage, api: api, endpoints: endpoints)
        worker = Worker(dataProviders: dataProviders, crypter: crypter, requestMaker: requestMaker)
        syncDidFinishPublisher = syncDidFinishSubject.eraseToAnyPublisher()
        syncQueue = SyncQueue()
    }

    func setUpAndStartFirstSync() async {
        await syncQueue.enqueue { [weak self] in
            guard let self else {
                return
            }
            let syncState = (try? self.storage.account()?.state) ?? .inactive

            for dataProvider in self.dataProviders {
                dataProvider.prepareForFirstSync()
            }

            switch syncState {
            case .setupNewAccount:
                if let account = try? self.storage.account()?.updatingState(.active) {
                    try? self.storage.persistAccount(account)
                }
            case .addNewDevice:
                try? await self.worker.sync(fetchOnly: true)
                if let account = try? self.storage.account()?.updatingState(.active) {
                    try? self.storage.persistAccount(account)
                }
            default:
                assertionFailure("Called first sync in unexpected \(syncState) state")
            }
        }
        await self.startSync()
    }

    func startSync() async {
        await syncQueue.enqueue { [weak self] in
            guard let self else {
                return
            }
            do {
                try await self.worker.sync(fetchOnly: false)
                self.syncDidFinishSubject.send(.success(()))
            } catch {
                print(error.localizedDescription)
                self.syncDidFinishSubject.send(.failure(error))
            }
        }
    }

    private let worker: WorkerProtocol
    private let syncDidFinishSubject = PassthroughSubject<Result<Void, Error>, Never>()
}
