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
    var dataProviders: [Feature: DataProviding] { get }
    /// Called to start sync
    func setUpAndStartFirstSync() async
    /// Called to start sync
    func startSync() async
    /// Emits events when sync each operation ends
    var syncDidFinishPublisher: AnyPublisher<Result<Void, Error>, Never> { get }
}

struct SyncResult {
    let feature: Feature
    let previousSyncTimestamp: String?
    let sent: [Syncable]

    var lastSyncTimestamp: String?
    var received: [Syncable] = []
}

actor Engine: EngineProtocol {

    let dataProviders: [Feature: DataProviding]
    let storage: SecureStoring
    let syncDidFinishPublisher: AnyPublisher<Result<Void, Error>, Never>
    let crypter: Crypting
    let requestMaker: SyncRequestMaking

    init(
        dataProviders: [DataProviding],
        storage: SecureStoring,
        crypter: Crypting,
        api: RemoteAPIRequestCreating,
        endpoints: Endpoints
    ) {
        var providersDictionary = [Feature: DataProviding]()
        for provider in dataProviders {
            providersDictionary[provider.feature] = provider
        }
        self.dataProviders = providersDictionary
        self.storage = storage
        self.crypter = crypter
        requestMaker = SyncRequestMaker(storage: storage, api: api, endpoints: endpoints)
        syncDidFinishPublisher = syncDidFinishSubject.eraseToAnyPublisher()
    }

    func setUpAndStartFirstSync() async {
        let syncState = (try? storage.account()?.state) ?? .inactive
        guard syncState != .inactive else {
            assertionFailure("Called first sync in unexpected \(syncState) state")
            return
        }

        await withTaskGroup(of: Void.self) { group in
            for dataProvider in dataProviders.values {
                group.addTask {
                    try? await dataProvider.prepareForFirstSync()
                }
            }
        }

        if syncState == .addNewDevice {
            try? await sync(fetchOnly: true)
        }

        if let account = try? storage.account()?.updatingState(.active) {
            try? storage.persistAccount(account)
        }

        await startSync()
    }

    func startSync() async {
        do {
            try await sync(fetchOnly: false)
            syncDidFinishSubject.send(.success(()))
        } catch {
            print(error.localizedDescription)
            syncDidFinishSubject.send(.failure(error))
        }
    }

    func sync(fetchOnly: Bool) async throws {
        print("Sync Operation Started. Fetch-only: \(fetchOnly)")
        defer {
            print("Sync Operation Finished. Fetch-only: \(fetchOnly)")
        }

        // Collect last sync timestamp and changes per feature
        var results = try await withThrowingTaskGroup(of: [Feature: SyncResult].self) { group in
            var results: [Feature: SyncResult] = [:]

            for dataProvider in self.dataProviders.values {
                let previousSyncTimestamp = dataProvider.lastSyncTimestamp
                if fetchOnly {
                    results[dataProvider.feature] = SyncResult(feature: dataProvider.feature, previousSyncTimestamp: previousSyncTimestamp, sent: [])
                } else {
                    let localChanges: [Syncable] = try await dataProvider.fetchChangedObjects(encryptedUsing: crypter)
                    let result = SyncResult(feature: dataProvider.feature, previousSyncTimestamp: previousSyncTimestamp, sent: localChanges)
                    results[dataProvider.feature] = result
                }
            }
            return results
        }

        let hasLocalChanges = results.values.contains(where: { !$0.sent.isEmpty })
        let request: HTTPRequesting = hasLocalChanges ? try requestMaker.makePatchRequest(with: results) : try requestMaker.makeGetRequest(with: results)
        let result: HTTPResult = try await request.execute()

        if let data = result.data {
            print("Response: \(String(data: data, encoding: .utf8)!)")
        }

        switch result.response.statusCode {
        case 200:
            guard let data = result.data else {
                throw SyncError.noResponseBody
            }
            try decodeResponse(with: data, into: &results)
            fallthrough
        case 204, 304:
            if fetchOnly {
                for (feature, result) in results {
                    try await dataProviders[feature]?.handleInitialSyncResponse(received: result.received, timestamp: result.lastSyncTimestamp, crypter: crypter)
                }
            } else {
                for (feature, result) in results {
                    try await dataProviders[feature]?.handleSyncResponse(sent: result.sent, received: result.received, timestamp: result.lastSyncTimestamp, crypter: crypter)
                }
            }
        default:
            throw SyncError.unexpectedStatusCode(result.response.statusCode)
        }
    }

    private func decodeResponse(with data: Data, into results: inout [Feature: SyncResult]) throws {
        guard let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw SyncError.unexpectedResponseBody
        }

        for feature in results.keys {
            guard let featurePayload = jsonObject[feature.name] as? [String: Any],
                let lastModified = featurePayload["last_modified"] as? String,
                let entries = featurePayload["entries"] as? [[String: Any]]
            else {
                throw SyncError.unexpectedResponseBody
            }
            results[feature]?.lastSyncTimestamp = lastModified
            results[feature]?.received = entries.map(Syncable.init(jsonObject:))
        }
    }

    private let syncDidFinishSubject = PassthroughSubject<Result<Void, Error>, Never>()
}
