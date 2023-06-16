//
//  SyncQueue.swift
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
import Common
import os

struct FeatureError: Error {
    let feature: Feature
    let underlyingError: Error
}

struct SyncOperationError: Error {
    let perFeatureErrors: [Feature: Error]

    init(featureErrors: [FeatureError]) {
        perFeatureErrors = featureErrors.reduce(into: .init() , { partialResult, featureError in
            partialResult[featureError.feature] = featureError.underlyingError
        })
    }
}

struct SyncRequest {
    let feature: Feature
    let previousSyncTimestamp: String?
    let sent: [Syncable]
}

struct SyncResult {
    let request: SyncRequest

    let syncTimestamp: String?
    let received: [Syncable]

    static func noData(with request: SyncRequest) -> SyncResult {
        SyncResult(request: request, syncTimestamp: nil, received: [])
    }
}

class SyncQueue {

    let dataProviders: [Feature: DataProviding]
    let storage: SecureStoring
    let isSyncInProgressPublisher: AnyPublisher<Bool, Never>
    let syncDidFinishPublisher: AnyPublisher<Result<Void, Error>, Never>
    let crypter: Crypting
    let requestMaker: SyncRequestMaking

    convenience init(dataProviders: [DataProviding], dependencies: SyncDependencies) {
        self.init(
            dataProviders: dataProviders,
            storage: dependencies.secureStore,
            crypter: dependencies.crypter,
            api: dependencies.api,
            endpoints: dependencies.endpoints,
            log: dependencies.log
        )
    }

    init(
        dataProviders: [DataProviding],
        storage: SecureStoring,
        crypter: Crypting,
        api: RemoteAPIRequestCreating,
        endpoints: Endpoints,
        log: @escaping @autoclosure () -> OSLog = .disabled
    ) {
        self.dataProviders = dataProviders.reduce(into: .init(), { partialResult, provider in
            partialResult[provider.feature] = provider
        })
        self.storage = storage
        self.crypter = crypter
        self.getLog = log
        requestMaker = SyncRequestMaker(storage: storage, api: api, endpoints: endpoints)
        syncDidFinishPublisher = syncDidFinishSubject.eraseToAnyPublisher()
        isSyncInProgressPublisher = Publishers
            .Merge(syncDidStartSubject.map({ true }), syncDidFinishSubject.map({ _ in false }))
            .prepend(false)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func prepareForFirstSync() throws {
        for dataProvider in dataProviders.values {
            do {
                try dataProvider.prepareForFirstSync()
            } catch {
                os_log(.debug, log: self.log, "Error when preparing %{public}s for first sync: %{public}s", dataProvider.feature.name, error.localizedDescription)
                dataProvider.handleSyncError(error)
                throw error
            }
        }
    }

    func startFirstSync(with completion: @escaping () -> Void) {
        let operation = makeSyncOperation(fetchOnly: true)
        scheduleSyncOperation(operation)
        operationQueue.addBarrierBlock(completion)
    }

    func startSync() {
        let operation = makeSyncOperation()
        scheduleSyncOperation(operation)
    }

    // MARK: - Concurrency

    func startFirstSync(with completion: @escaping () -> Void) async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let operation = makeSyncOperation(fetchOnly: true)
            scheduleSyncOperation(operation)
            operationQueue.addBarrierBlock {
                completion()
                continuation.resume()
            }
        }
    }

    func startSync() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let operation = makeSyncOperation()
            scheduleSyncOperation(operation)
            operationQueue.addBarrierBlock {
                continuation.resume()
            }
        }
    }

    // MARK: - Private

    private func scheduleSyncOperation(_ operation: SyncOperation) {
        operationQueue.addBarrierBlock { [weak self] in
            self?.syncDidStartSubject.send(())
        }
        operationQueue.addOperation(operation)
        operationQueue.addBarrierBlock { [weak self] in
            if let error = operation.error {
                self?.syncDidFinishSubject.send(.failure(error))
            } else {
                self?.syncDidFinishSubject.send(.success(()))
            }
        }
    }

    private func makeSyncOperation(fetchOnly: Bool = false) -> SyncOperation {
        SyncOperation(fetchOnly: fetchOnly, dataProviders: dataProviders, storage: storage, crypter: crypter, requestMaker: requestMaker, log: self.log)
    }

    private let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.duckduckgo.sync.queue"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private let syncDidFinishSubject = PassthroughSubject<Result<Void, Error>, Never>()
    private let syncDidStartSubject = PassthroughSubject<Void, Never>()
    private var log: OSLog {
        getLog()
    }
    private let getLog: () -> OSLog
}
