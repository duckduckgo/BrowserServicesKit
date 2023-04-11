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
 * Internal interface for sync schedulers.
 */
protocol SchedulingInternal: Scheduling {
    /// Publishes events to notify Sync Engine that sync operation should be started.
    var startSyncPublisher: AnyPublisher<Void, Never> { get }
}

/**
 * Internal interface for sync engine.
 */
protocol EngineProtocol: ResultsPublishing {
    /// Used for passing data to sync
    var dataProviders: [DataProviding] { get }
    /// Called to start sync
    func startSync()
}

/**
 * Internal interface for sync worker.
 */
protocol WorkerProtocol {
    var dataProviders: [Feature: DataProviding] { get }

    func sync() async throws -> [ResultsProviding]
}

// MARK: - Example Implementation

class SyncScheduler: SchedulingInternal {
    func notifyDataChanged() {
        syncTriggerSubject.send()
    }

    func notifyAppLifecycleEvent() {
        appLifecycleEventSubject.send()
    }

    func requestSyncImmediately() {
        syncTriggerSubject.send()
    }

    let startSyncPublisher: AnyPublisher<Void, Never>

    init() {
        let throttledAppLifecycleEvents = appLifecycleEventSubject
            .throttle(for: .seconds(Const.appLifecycleEventsDebounceInterval), scheduler: DispatchQueue.main, latest: true)

        let throttledSyncTriggerEvents = syncTriggerSubject
            .throttle(for: .seconds(Const.immediateSyncDebounceInterval), scheduler: DispatchQueue.main, latest: true)

        startSyncPublisher = startSyncSubject.eraseToAnyPublisher()

        startSyncCancellable = Publishers.Merge(throttledAppLifecycleEvents, throttledSyncTriggerEvents)
            .sink(receiveValue: { [weak self] _ in
                self?.startSyncSubject.send()
            })
    }

    private let appLifecycleEventSubject: PassthroughSubject<Void, Never> = .init()
    private let syncTriggerSubject: PassthroughSubject<Void, Never> = .init()
    private let startSyncSubject: PassthroughSubject<Void, Never> = .init()
    private var startSyncCancellable: AnyCancellable?

    enum Const {
        static let immediateSyncDebounceInterval = 1
        static let appLifecycleEventsDebounceInterval = 600
    }
}

struct ResultsProvider: ResultsProviding {
    let feature: Feature

    var lastSyncTimestamp: String?

    var sent: [Syncable] = []
    var received: [Syncable] = []
}

class Engine: EngineProtocol {

    let dataProviders: [DataProviding]
    let results: AnyPublisher<[ResultsProviding], Never>

    init(
        dataProviders: [DataProviding],
        api: RemoteAPIRequestCreating,
        endpoints: Endpoints
    ) {
        self.dataProviders = dataProviders
        self.worker = Worker(dataProviders: dataProviders, api: api, endpoints: endpoints)

        results = resultsSubject.eraseToAnyPublisher()
    }

    func startSync() {
        Task {
            let results = try await worker.sync()
            resultsSubject.send(results)
        }
    }

    private let worker: WorkerProtocol
    private let resultsSubject = PassthroughSubject<[ResultsProviding], Never>()
}

actor Worker: WorkerProtocol {

    let dataProviders: [Feature: DataProviding]
    let endpoints: Endpoints
    let api: RemoteAPIRequestCreating

    init(
        dataProviders: [DataProviding],
        api: RemoteAPIRequestCreating,
        endpoints: Endpoints
    ) {
        var providersDictionary = [Feature: DataProviding]()
        for provider in dataProviders {
            providersDictionary[provider.feature] = provider
        }
        self.dataProviders = providersDictionary
        self.endpoints = endpoints
        self.api = api
    }

    func sync() async throws -> [ResultsProviding] {

        // Collect last sync timestamp and changes per feature
        var results = try await withThrowingTaskGroup(of: [Feature: ResultsProvider].self) { group in
            var results: [Feature: ResultsProvider] = [:]

            for dataProvider in self.dataProviders.values {
                let localChanges = try await dataProvider.changes(since: dataProvider.lastSyncTimestamp)
                let resultProvider = ResultsProvider(feature: dataProvider.feature, sent: localChanges)
                results[dataProvider.feature] = resultProvider
            }
            return results
        }

        let hasLocalChanges = results.values.contains(where: { !$0.sent.isEmpty })

        let request: HTTPRequesting = hasLocalChanges ? try makePatchRequest(with: results) : try makeGetRequest(for: Array(dataProviders.keys))
        let result: HTTPResult = try await request.execute()

        guard let data = result.data else {
            throw SyncError.noResponseBody
        }

        guard let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw SyncError.unexpectedResponseBody
        }

        for feature in results.keys {
            guard let featurePayload = jsonObject[feature.name] as? [String: Any] else {
                throw SyncError.unexpectedResponseBody
            }
            results[feature]?.lastSyncTimestamp = featurePayload["last_modified"] as? String
            results[feature]?.received = featurePayload["entries"] as! [Syncable]
        }

        return Array(results.values)
    }

    private func makeGetRequest(for features: [Feature]) throws -> HTTPRequesting {
        let url = try endpoints.syncGet(features: features.map(\.name))
        return api.createRequest(url: url, method: .GET, headers: [:], parameters: [:], body: nil, contentType: nil)
    }

    private func makePatchRequest(with results: [Feature: ResultsProviding]) throws -> HTTPRequesting {
        var json = [String: Any]()
        for (feature, result) in results {
            let modelPayload: [String: Any?] = [
                "updates": result.sent.map(\.payload),
                "modified_since": dataProviders[feature]?.lastSyncTimestamp
            ]
            json[feature.name] = modelPayload
        }

        let body = try JSONSerialization.data(withJSONObject: json, options: [])
        return api.createRequest(url: endpoints.syncPatch, method: .PATCH, headers: [:], parameters: [:], body: body, contentType: "application/json")
    }
}
