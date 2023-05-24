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

actor SyncQueue: SyncQueueProtocol {

    let dataProviders: [Feature: DataProviding]
    let storage: SecureStoring
    let isSyncInProgressPublisher: AnyPublisher<Bool, Never>
    let syncDidFinishPublisher: AnyPublisher<Result<Void, Error>, Never>
    nonisolated let crypter: Crypting
    nonisolated let requestMaker: SyncRequestMaking

    init(dataProviders: [DataProviding], dependencies: SyncDependencies) {
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

    nonisolated func prepareForFirstSync() throws {
        for dataProvider in dataProviders.values {
            try dataProvider.prepareForFirstSync()
        }
    }

    func startFirstSync() async {
        do {
            syncDidStartSubject.send(())
            let syncAuthState = (try? storage.account()?.state) ?? .inactive
            guard syncAuthState != .inactive else {
                assertionFailure("Called first sync in unexpected \(syncAuthState) state")
                return
            }

            if syncAuthState == .addingNewDevice {
                try await sync(fetchOnly: true)
            }
            syncDidFinishSubject.send(.success(()))
        } catch {
            syncDidFinishSubject.send(.failure(error))
        }
    }

    func startSync() async {
        do {
            syncDidStartSubject.send(())
            try await sync(fetchOnly: false)
            syncDidFinishSubject.send(.success(()))
        } catch {
            syncDidFinishSubject.send(.failure(error))
        }
    }

    /**
     * This is private to SyncQueue, but not marked as such to allow unit testing.
     */
    func sync(fetchOnly: Bool) async throws {
        os_log(.debug, log: log, "Sync Operation Started. Fetch-only: %{public}s", String(fetchOnly))
        defer {
            os_log(.debug, log: log, "Sync Operation Finished. Fetch-only: %{public}s", String(fetchOnly))
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (feature, dataProvider) in dataProviders {
                group.addTask { [weak self] in
                    guard let self else {
                        return
                    }
                    os_log(.debug, log: self.log, "Syncing %{public}s", feature.name)

                    do {
                        let syncRequest = try await self.makeSyncRequest(for: dataProvider, fetchOnly: fetchOnly)
                        let clientTimestamp = Date()
                        let httpRequest = try self.makeHTTPRequest(with: syncRequest, timestamp: clientTimestamp)
                        let httpResult: HTTPResult = try await httpRequest.execute()

                        switch httpResult.response.statusCode {
                        case 200:
                            guard let data = httpResult.data else {
                                throw SyncError.noResponseBody
                            }
                            os_log(.debug, log: self.log, "Response for %{public}s: %{public}s",
                                   feature.name,
                                   String(data: data, encoding: .utf8) ?? "")
                            let syncResult = try self.decodeResponse(with: data, request: syncRequest)
                            try await self.handleResponse(for: dataProvider, syncResult: syncResult, fetchOnly: fetchOnly, timestamp: clientTimestamp)
                        case 204, 304:
                            try await self.handleResponse(for: dataProvider, syncResult: .noData(with: syncRequest), fetchOnly: fetchOnly, timestamp: clientTimestamp)
                        default:
                            throw SyncError.unexpectedStatusCode(httpResult.response.statusCode)
                        }
                    } catch {
                        os_log(.debug, log: self.log, "Error syncing %{public}s: %{public}s", feature.name, error.localizedDescription)
                        dataProvider.handleSyncError(error)
                        throw FeatureError(feature: feature, underlyingError: error)
                    }
                }
            }

            var errors: [FeatureError] = []

            while let result = await group.nextResult() {
                if case .failure(let error) = result, let featureError = error as? FeatureError {
                    errors.append(featureError)
                }
            }

            if !errors.isEmpty {
                throw SyncOperationError(featureErrors: errors)
            }
        }
    }

    nonisolated private func makeSyncRequest(for dataProvider: DataProviding, fetchOnly: Bool) async throws -> SyncRequest {
        if fetchOnly {
            return SyncRequest(feature: dataProvider.feature, previousSyncTimestamp: dataProvider.lastSyncTimestamp, sent: [])
        }
        let localChanges: [Syncable] = try await dataProvider.fetchChangedObjects(encryptedUsing: crypter)
        return SyncRequest(feature: dataProvider.feature, previousSyncTimestamp: dataProvider.lastSyncTimestamp, sent: localChanges)
    }

    nonisolated private func makeHTTPRequest(with syncRequest: SyncRequest, timestamp: Date) throws -> HTTPRequesting {
        let hasLocalChanges = !syncRequest.sent.isEmpty
        if hasLocalChanges {
            return try requestMaker.makePatchRequest(with: syncRequest, clientTimestamp: timestamp)
        }
        return try requestMaker.makeGetRequest(with: syncRequest)
    }

    nonisolated private func decodeResponse(with data: Data, request: SyncRequest) throws -> SyncResult {
        guard let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw SyncError.unexpectedResponseBody
        }

        guard let featurePayload = jsonObject[request.feature.name] as? [String: Any],
              let lastModified = featurePayload["last_modified"] as? String,
              let entries = featurePayload["entries"] as? [[String: Any]]
        else {
            throw SyncError.unexpectedResponseBody
        }
        return SyncResult(request: request, syncTimestamp: lastModified, received: entries.map(Syncable.init(jsonObject:)))
    }

    nonisolated private func handleResponse(for dataProvider: DataProviding, syncResult: SyncResult, fetchOnly: Bool, timestamp: Date) async throws {
        if fetchOnly {
            try await dataProvider.handleInitialSyncResponse(
                received: syncResult.received,
                clientTimestamp: timestamp,
                serverTimestamp: syncResult.syncTimestamp,
                crypter: crypter
            )
        } else {
            try await dataProvider.handleSyncResponse(
                sent: syncResult.request.sent,
                received: syncResult.received,
                clientTimestamp: timestamp,
                serverTimestamp: syncResult.syncTimestamp,
                crypter: crypter
            )
        }
    }

    private let syncDidFinishSubject = PassthroughSubject<Result<Void, Error>, Never>()
    private let syncDidStartSubject = PassthroughSubject<Void, Never>()
    nonisolated private var log: OSLog {
        getLog()
    }
    nonisolated private let getLog: () -> OSLog
}
