//
//  SyncQueue.swift
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

struct FeatureError: Error {
    let feature: Feature
    let underlyingError: Error
}

struct SyncOperationError: Error {
    let perFeatureErrors: [Feature: Error]

    init(featureErrors: [FeatureError]) {
        perFeatureErrors = featureErrors.reduce(into: .init()) { partialResult, featureError in
            partialResult[featureError.feature] = featureError.underlyingError
        }
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

final class SyncQueue {

    let dataProviders: [DataProviding]
    let storage: SecureStoring
    let isSyncInProgressPublisher: AnyPublisher<Bool, Never>
    let syncDidFinishPublisher: AnyPublisher<Result<Void, Error>, Never>
    let syncHTTPRequestErrorPublisher: AnyPublisher<Error, Never>
    let crypter: Crypting
    let requestMaker: SyncRequestMaking

    convenience init(dataProviders: [DataProviding], dependencies: SyncDependencies) {
        self.init(
            dataProviders: dataProviders,
            storage: dependencies.secureStore,
            crypter: dependencies.crypter,
            api: dependencies.api,
            endpoints: dependencies.endpoints,
            payloadCompressor: dependencies.payloadCompressor,
            log: dependencies.log
        )
    }

    init(
        dataProviders: [DataProviding],
        storage: SecureStoring,
        crypter: Crypting,
        api: RemoteAPIRequestCreating,
        endpoints: Endpoints,
        payloadCompressor: SyncPayloadCompressing,
        log: @escaping @autoclosure () -> OSLog = .disabled
    ) {
        self.dataProviders = dataProviders
        self.storage = storage
        self.crypter = crypter
        self.getLog = log
        requestMaker = SyncRequestMaker(storage: storage, api: api, endpoints: endpoints, payloadCompressor: payloadCompressor)
        syncDidFinishPublisher = syncDidFinishSubject.eraseToAnyPublisher()
        syncHTTPRequestErrorPublisher = syncHTTPRequestErrorSubject.eraseToAnyPublisher()
        isSyncInProgressPublisher = Publishers
            .Merge(syncDidStartSubject.map({ true }), syncDidFinishSubject.map({ _ in false }))
            .prepend(false)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func prepareDataModelsForSync(needsRemoteDataFetch: Bool) throws {
        let unregisteredDataProviders = dataProviders.filter { !$0.isFeatureRegistered }
        guard !unregisteredDataProviders.isEmpty else {
            return
        }

        let hasRegisteredDataProviders = unregisteredDataProviders.count != dataProviders.count
        let setupState: FeatureSetupState = (needsRemoteDataFetch || hasRegisteredDataProviders) ? .needsRemoteDataFetch : .readyToSync

        for dataProvider in unregisteredDataProviders {
            do {
                try dataProvider.prepareForFirstSync()
                try dataProvider.registerFeature(withState: setupState)
            } catch {
                os_log(.debug, log: self.log, "Error when preparing %{public}s for first sync: %{public}s", dataProvider.feature.name, error.localizedDescription)
                dataProvider.handleSyncError(error)
                throw error
            }
        }
    }

    var isDataSyncingFeatureFlagEnabled: Bool = true {
        didSet {
            if isDataSyncingFeatureFlagEnabled {
                os_log(.debug, log: self.log, "Sync Feature has been enabled")
            } else {
                os_log(.debug, log: self.log, "Sync Feature has been disabled, cancelling all operations")
                operationQueue.cancelAllOperations()
            }
        }
    }

    func startSync() {
        guard isDataSyncingFeatureFlagEnabled else {
            os_log(.debug, log: self.log, "Sync Feature is temporarily disabled, not starting sync")
            return
        }
        let operation = makeSyncOperation()
        operationQueue.addOperation(operation)
    }

    func cancelOngoingSyncAndSuspendQueue() {
        os_log(.debug, log: self.log, "Cancelling sync and suspending sync queue")
        operationQueue.cancelAllOperations()
        operationQueue.isSuspended = true
    }

    func resumeQueue() {
        os_log(.debug, log: self.log, "Resuming sync queue")
        operationQueue.isSuspended = false
    }

    // MARK: - Private

    private func makeSyncOperation() -> SyncOperation {
        let operation = SyncOperation(
            dataProviders: dataProviders,
            storage: storage,
            crypter: crypter,
            requestMaker: requestMaker,
            log: self.log
        )
        operation.didStart = { [weak self] in
            self?.syncDidStartSubject.send(())
        }
        operation.didFinish = { [weak self] error in
            if let error {
                self?.syncDidFinishSubject.send(.failure(error))
            } else {
                self?.syncDidFinishSubject.send(.success(()))
            }
        }
        operation.didReceiveHTTPRequestError = { [weak self] error in
            self?.syncHTTPRequestErrorSubject.send(error)
        }

        return operation
    }

    let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.duckduckgo.sync.queue"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private let syncDidFinishSubject = PassthroughSubject<Result<Void, Error>, Never>()
    private let syncDidStartSubject = PassthroughSubject<Void, Never>()
    private let syncHTTPRequestErrorSubject = PassthroughSubject<Error, Never>()
    private var log: OSLog {
        getLog()
    }
    private let getLog: () -> OSLog
}
